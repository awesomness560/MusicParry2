extends Node
## Autoload "CombatResolver". Collects parry presses and impacts, judges each impact
## once its late window closes, and broadcasts the result for anyone to listen to.

signal attack_resolved(result: AttackResult)          # once per attack
signal beat_resolved(results: Array[AttackResult])    # once per beat, all attacks that landed on it
signal parry_whiffed(press_time: float)

@export var early_window := 0.12
@export var late_window := 0.045
@export var perfect_early := 0.05
@export var perfect_late := 0.025

var _pending: Array[AttackRequest] = []
var _presses: Array[Dictionary] = []     # { "t": float, "used": bool }


func _ready() -> void:
	process_priority = -800              # after the scheduler, so impacts arrive the same frame
	AttackScheduler.attack_impact.connect(_on_attack_impact)
	Conductor.time_jumped.connect(_on_time_jumped)


func register_press(t: float) -> void:
	_presses.append({ "t": t, "used": false })


func _on_attack_impact(r: AttackRequest) -> void:
	_pending.append(r)


func _on_time_jumped(_t: float) -> void:
	_pending.clear()
	_presses.clear()


func _process(_delta: float) -> void:
	if not Conductor.playing or Conductor.stream_paused:
		return
	var now := Conductor.song_time

	# collect impacts whose late window has closed, grouped by beat
	var by_beat := {}                    # beat index -> Array[AttackRequest]
	for r in _pending.duplicate():
		if now >= r.impact_time + late_window:
			_pending.erase(r)
			if not by_beat.has(r.impact_beat):
				var arr: Array[AttackRequest] = []
				by_beat[r.impact_beat] = arr
			by_beat[r.impact_beat].append(r)

	var beats := by_beat.keys()
	beats.sort()
	for b in beats:
		var group: Array[AttackRequest] = by_beat[b]
		var results: Array[AttackResult] = []
		for r in group:
			var res := _judge(r)
			res.group = group
			results.append(res)
			attack_resolved.emit(res)
		beat_resolved.emit(results)

	# presses too old to parry anything: unused ones are whiffs
	var cutoff := now - early_window - late_window
	var keep: Array[Dictionary] = []
	for p in _presses:
		if p["t"] > cutoff:
			keep.append(p)
		elif not p["used"]:
			parry_whiffed.emit(p["t"])
	_presses = keep


func _judge(r: AttackRequest) -> AttackResult:
	var res := AttackResult.new()
	res.request = r
	var t := r.impact_time

	# closest press inside [impact - early, impact + late]; one press can parry several attacks
	var best := -1
	for i in _presses.size():
		var pt: float = _presses[i]["t"]
		if pt < t - early_window or pt > t + late_window:
			continue
		if best == -1 or absf(pt - t) < absf(_presses[best]["t"] - t):
			best = i

	if best == -1:
		res.outcome = AttackResult.Outcome.HIT
		return res

	_presses[best]["used"] = true
	res.offset = _presses[best]["t"] - t
	var perfect := res.offset >= -perfect_early and res.offset <= perfect_late
	res.outcome = AttackResult.Outcome.PERFECT_PARRY if perfect else AttackResult.Outcome.PARRY
	return res
