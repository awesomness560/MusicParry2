extends Control
class_name BeatPulse
## Add as a child of any Control or Node2D to make it pulse on the beat.

@export var amount := 0.12            # extra scale at the peak (0.12 = 12% bigger)
@export var sharpness := 4.0          # higher = snappier decay after the hit
@export var every_n_beats := 1        # 1 = every beat, 2 = every other, 4 = every bar
@export var beat_offset := 0          # shifts which beat in the pattern it hits on
@export var pulse_brightness := 0.0   # 0 = off, 0.5 = flashes 50% brighter on the beat

var _target: CanvasItem
var _base_scale := Vector2.ONE
var _base_modulate := Color.WHITE


func _ready() -> void:
	_target = get_parent() as CanvasItem
	if not (_target is Control or _target is Node2D):
		push_warning("BeatPulse: parent must be a Control or Node2D")
		set_process(false)
		return
	_base_scale = _target.scale
	_base_modulate = _target.modulate


func _process(_delta: float) -> void:
	var env := _envelope()

	if _target is Control:
		var c := _target as Control
		c.pivot_offset = c.size * 0.5     # scale from the centre, not the top-left
	_target.scale = _base_scale * (1.0 + amount * env)
	_target.modulate = _base_modulate * (1.0 + pulse_brightness * env)


# 1.0 exactly on a pattern beat, decaying to 0 over the following beat
func _envelope() -> float:
	if not Conductor.playing or Conductor.stream_paused:
		return 0.0
	var b := Conductor.song_beat - beat_offset
	if b < 0.0:
		return 0.0                          # before the first beat of the song
	var since := fposmod(b, float(maxi(every_n_beats, 1)))   # beats since the last pattern beat
	return pow(maxf(1.0 - since, 0.0), sharpness)
