extends Node
## Autoload "Style". Owns style points and rank. Anything can report what happened;
## the _score functions decide what it's worth. The UI, scheduler and enemies read from here.

signal award(text: String, points: float, color: Color, key: StringName)
signal rank_changed(new_rank: int, old_rank: int, rank_up: bool)

@export_group("Points")
@export var parry_points := 70.0
@export var perfect_points := 120.0
@export var multi_bonus := 50.0          # extra per additional parry on the same beat
@export var hits_cost_style := false
@export var hit_penalty := 350.0

@export_group("Colours")
@export var parry_color := Color.WHITE
@export var perfect_color := Color(1.0, 0.72, 0.3)
@export var multi_color := Color(0.68, 0.62, 1.0)
@export var hit_color := Color(1.0, 0.35, 0.3)

@export_group("Decay")
@export var grace_beats := 2.0           # beats after your last gain before decay starts
@export var constant_decay_from := 4     # rank index from which decay ignores the grace period (4 = S)
@export var brink_fraction := 0.2        # warn when the bar is below this fraction of the current rank
@export var save_beats := 2.0            # beats to save the rank once the bar is empty
@export var drop_refill := 0.5           # how full the lower rank's bar is after failing a save

# at = points needed, decay = points lost per second
# pulse: beat = every beat, down = first beat of the bar, off = the "and" between beats
const RANKS := [
	{ "name": "D",   "title": "Ignored",     "color": Color(0.55, 0.55, 0.55), "at": 0.0,
	  "decay": 15.0,  "beat": 0.0,  "down": 0.0, "off": 0.0, "tilt": false, "shift": false },
	{ "name": "C",   "title": "Noticed",     "color": Color(0.72, 0.84, 0.96), "at": 300.0,
	  "decay": 25.0,  "beat": 0.0,  "down": 0.6, "off": 0.0, "tilt": false, "shift": false },
	{ "name": "B",   "title": "Watched",     "color": Color(0.47, 0.67, 0.93), "at": 700.0,
	  "decay": 40.0,  "beat": 0.35, "down": 0.0, "off": 0.0, "tilt": false, "shift": false },
	{ "name": "A",   "title": "Admired",     "color": Color(0.67, 0.6, 0.96),  "at": 1200.0,
	  "decay": 55.0,  "beat": 0.7,  "down": 0.0, "off": 0.0, "tilt": false, "shift": false },
	{ "name": "S",   "title": "Feared",      "color": Color(0.96, 0.62, 0.2),  "at": 1800.0,
	  "decay": 75.0,  "beat": 0.7,  "down": 1.0, "off": 0.0, "tilt": false, "shift": false },
	{ "name": "SS",  "title": "Blasphemous", "color": Color(0.97, 0.74, 0.4),  "at": 2600.0,
	  "decay": 95.0,  "beat": 0.8,  "down": 1.0, "off": 0.4, "tilt": true,  "shift": false },
	{ "name": "SSS", "title": "Deicide",     "color": Color(0.97, 0.8, 0.45),  "at": 3500.0,
	  "decay": 120.0, "beat": 1.0,  "down": 1.2, "off": 0.5, "tilt": true,  "shift": true },
]
const MAX_POINTS := 4500.0

var points := 0.0
var rank := 0
var warning := 0.0                       # 0..1, read by the UI each frame

var _last_action_beat := -INF
var _save_until_beat := -1.0             # >= 0 while a save window is open
var _modifiers := {}                     # source -> [kind, multiplier, until_time]
var _context_provider: Callable


func _ready() -> void:
	process_priority = -700              # after the resolver, before the UI
	CombatResolver.beat_resolved.connect(_on_beat_resolved)
	Conductor.time_jumped.connect(func(_t): reset())


# ================================================================ public API

## Report something that happened. id = what (&"parry", &"kill", &"trick"),
## tags = descriptors (&"perfect", &"aerial"), context = details (kind, speed, beat...).
func report(id: StringName, tags: Array = [], context := {}) -> void:
	tags = tags.duplicate()
	context = context.duplicate()
	if _context_provider.is_valid():
		var c: Dictionary = _context_provider.call()
		for t in c.get("tags", []):
			if not tags.has(t):
				tags.append(t)
		for k in c:
			if k != "tags" and not context.has(k):
				context[k] = c[k]
	_score(id, tags, context)
	_points_changed()


## The player registers a function returning its state, e.g. { "tags": [&"aerial"], "speed": 14.0 }.
## It's merged into every reported event.
func set_context_provider(provider: Callable) -> void:
	_context_provider = provider


## Ongoing effects keyed by source, e.g. add_modifier(&"twirl", &"decay", 0.0) while twirling.
## kind is &"decay" or &"score". duration > 0 expires after that many seconds of song time.
func add_modifier(source: StringName, kind: StringName, multiplier: float, duration := 0.0) -> void:
	var until := Conductor.song_time + duration if duration > 0.0 else INF
	_modifiers[source] = [kind, multiplier, until]


func remove_modifier(source: StringName) -> void:
	_modifiers.erase(source)


func get_multiplier(kind: StringName) -> float:
	var m := 1.0
	for mod in _modifiers.values():
		if mod[0] == kind:
			m *= mod[1]
	return m


func current_rank() -> Dictionary:
	return RANKS[rank]


## 0..1 progress through the current rank.
func progress() -> float:
	var lo: float = RANKS[rank]["at"]
	var hi: float = RANKS[rank + 1]["at"] if rank + 1 < RANKS.size() else MAX_POINTS
	return clampf((points - lo) / maxf(hi - lo, 1.0), 0.0, 1.0)


func is_saving() -> bool:
	return _save_until_beat >= 0.0


func reset() -> void:
	var old := rank
	points = 0.0
	rank = 0
	warning = 0.0
	_save_until_beat = -1.0
	_last_action_beat = -INF
	_modifiers.clear()
	_multi_beat = -1
	_multi_count = 0
	if old != 0:
		rank_changed.emit(0, old, false)


# ================================================================ combat -> events

func _on_beat_resolved(results: Array[AttackResult]) -> void:
	for res in results:
		var kind := String(res.request.attack_kind)
		var ctx := { "kind": kind, "beat": res.request.impact_beat, "offset": res.offset,
				"attacker": res.request.attacker }
		if res.is_parry():
			var tags: Array = [StringName(kind)]
			if res.outcome == AttackResult.Outcome.PERFECT_PARRY:
				tags.append(&"perfect")
			report(&"parry", tags, ctx)
		else:
			report(&"hit", [StringName(kind)], ctx)


# ================================================================ scoring

func _score(id: StringName, tags: Array, ctx: Dictionary) -> void:
	match id:
		&"parry": _score_parry(tags, ctx)
		&"hit": _score_hit(tags, ctx)


func _score_parry(tags: Array, ctx: Dictionary) -> void:
	var kind: String = ctx.get("kind", "")
	if &"perfect" in tags:
		_give("Perfect %s parry" % kind, perfect_points, perfect_color)
	else:
		_give("%s parry" % kind.capitalize(), parry_points, parry_color)

	_check_multi_parry(ctx)


func _score_hit(_tags: Array, _ctx: Dictionary) -> void:
	if hits_cost_style:
		_give("Hit taken", -hit_penalty, hit_color)


## Adds points and shows the feed line. Gains count as an action (grace period, saves).
func _give(text: String, pts: float, color: Color, key: StringName = &"") -> void:
	if pts > 0.0:
		pts *= get_multiplier(&"score")
		_last_action_beat = Conductor.song_beat
		_save_until_beat = -1.0
	points += pts
	award.emit(text, pts, color, key)


# ---------------------------------------------------------------- combos

var _multi_beat := -1
var _multi_count := 0

## Several parries on the same beat.
func _check_multi_parry(ctx: Dictionary) -> void:
	var beat: int = ctx.get("beat", -1)
	if beat != _multi_beat:
		_multi_beat = beat
		_multi_count = 0
	_multi_count += 1
	if _multi_count >= 2:
		_give("Multi-parry", multi_bonus, multi_color, &"multi_parry")


# ================================================================ decay, saves, ranks

func _process(delta: float) -> void:
	var playing := Conductor.playing and not Conductor.stream_paused

	for source in _modifiers.keys():
		if Conductor.song_time >= _modifiers[source][2]:
			_modifiers.erase(source)

	# decay waits for the grace period, except at high ranks; modifiers can slow or stop it
	var decay_rate: float = RANKS[rank]["decay"] * get_multiplier(&"decay")
	var in_grace := Conductor.song_beat - _last_action_beat <= grace_beats and rank < constant_decay_from
	var decaying := playing and points > 0.0 and not in_grace and decay_rate > 0.0
	if decaying:
		points -= decay_rate * delta
		_points_changed()

	# save window: frozen while decay is stopped, otherwise runs out into a rank-down
	if is_saving() and playing:
		if decay_rate <= 0.0:
			_save_until_beat += delta / Conductor.seconds_per_beat()
		elif Conductor.song_beat >= _save_until_beat:
			_save_until_beat = -1.0
			_drop_rank()

	if is_saving():
		warning = 1.0
	elif decaying and rank > 0 and progress() < brink_fraction:
		warning = 1.0 - progress() / brink_fraction
	else:
		warning = 0.0


func _points_changed() -> void:
	points = clampf(points, 0.0, MAX_POINTS)

	var target := _rank_for(points)
	if target > rank:
		_save_until_beat = -1.0
		_set_rank(target, true)

	# can't fall out of a rank by points alone: hold at the floor and open a save window
	var lo: float = RANKS[rank]["at"]
	if rank > 0 and points <= lo:
		points = lo
		if not is_saving():
			_save_until_beat = Conductor.song_beat + save_beats


func _drop_rank() -> void:
	var r := rank - 1
	points = lerpf(RANKS[r]["at"], RANKS[r + 1]["at"], drop_refill)
	_set_rank(r, false)


func _set_rank(r: int, up: bool) -> void:
	var old := rank
	rank = r
	rank_changed.emit(r, old, up)


func _rank_for(p: float) -> int:
	var r := 0
	for i in RANKS.size():
		if p >= RANKS[i]["at"]:
			r = i
	return r
