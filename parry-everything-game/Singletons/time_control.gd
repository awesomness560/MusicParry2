extends Node
## Slows the game (Engine.time_scale) and the music (Conductor.pitch_scale) together, so the song,
## its beats and the attacks scheduled on them all slow with the world and stay in sync.
## Several things can ask at once (hold dash, hitstop, perfect parry): the slowest request wins.

signal scale_changed(scale: float)

@export var blend_speed := 25.0         ## how fast time eases toward its target, per real second

var _requests := {}                     # source -> [scale, until (real seconds, INF = until released)]
var _scale := 1.0
var _last_real := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_last_real = _real_now()


## Ask for time to run at `scale` (0..1). duration > 0 ends it automatically after that many REAL seconds.
## instant = jump straight there instead of easing (for hitstop).
func request(source: StringName, scale: float, duration := 0.0, instant := false) -> void:
	var until := _real_now() + duration if duration > 0.0 else INF
	_requests[source] = [clampf(scale, 0.01, 1.0), until]
	if instant:
		_set_scale(minf(_scale, scale))


func release(source: StringName) -> void:
	_requests.erase(source)


func current() -> float:
	return _scale


func _process(_delta: float) -> void:
	# _delta is itself slowed down, so use real time for everything here.
	var now := _real_now()
	var real_dt := now - _last_real
	_last_real = now

	var target := 1.0
	for source in _requests.keys():
		if now >= _requests[source][1]:
			_requests.erase(source)
		else:
			target = minf(target, _requests[source][0])

	var s := lerpf(_scale, target, 1.0 - exp(-blend_speed * real_dt))
	if absf(s - target) < 0.005:
		s = target
	_set_scale(s)


func _set_scale(s: float) -> void:
	if is_equal_approx(s, _scale):
		return
	_scale = s
	Engine.time_scale = s
	Conductor.pitch_scale = s           # the song slows (and pitches down) with the world
	scale_changed.emit(s)


func _real_now() -> float:
	return Time.get_ticks_usec() / 1_000_000.0
