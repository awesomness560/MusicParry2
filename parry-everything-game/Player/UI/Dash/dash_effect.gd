extends ColorRect
class_name DashEffect
## Full-screen dash effect. Tap: blips in and out. Hold: builds while aiming, held through the dash.
## Only listens to signals on `source` (connected by name, no class dependency):
##   dashed(direction: Vector3, is_hold: bool, duration: float)
##   dash_aim_started(max_hold: float)
##   dash_aim_ended()

@export var source: Node                ## the node that emits the dash signals (PlayerMovement)

@export_group("Tap")
@export_range(0.0, 1.0) var tap_strength := 0.8
@export var tap_attack := 80.0          ## how fast it blips in
@export var tap_release := 14.0         ## how fast it blips out
@export var tap_extra := 0.0            ## extra seconds held after the zip

@export_group("Hold")
@export_range(0.0, 1.0) var aim_strength := 0.5   ## level while aiming
@export var aim_attack := 12.0          ## how fast it builds when aiming starts
@export_range(0.0, 1.0) var hold_strength := 1.0  ## level during the hold dash itself
@export var hold_attack := 40.0
@export var hold_release := 6.0         ## slower fade out than the tap
@export var hold_extra := 0.05

var _level := 0.0
var _peak := 0.0
var _sustain_left := 0.0                # game seconds left at the peak
var _attack := 0.0
var _release := 10.0
var _aiming := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	source.connect(&"dashed", _on_dashed)
	source.connect(&"dash_aim_started", _on_aim_started)
	source.connect(&"dash_aim_ended", _on_aim_ended)
	visible = false


func _process(delta: float) -> void:
	var real_dt := delta / maxf(Engine.time_scale, 0.0001)   # fades use real time, even in slow motion
	_sustain_left -= delta                                   # the peak lasts as long as the dash (game time)

	var target := 0.0
	var rate := _release
	if _aiming:
		target = aim_strength
		rate = aim_attack
	elif _sustain_left > 0.0:
		target = _peak
		rate = _attack

	_level = lerpf(_level, target, 1.0 - exp(-rate * real_dt))
	if target == 0.0 and _level < 0.002:
		_level = 0.0

	visible = _level > 0.0              # skip the screen read entirely when idle
	(material as ShaderMaterial).set_shader_parameter("intensity", _level)


func _on_dashed(_direction: Vector3, is_hold: bool, duration: float) -> void:
	_peak = hold_strength if is_hold else tap_strength
	_attack = hold_attack if is_hold else tap_attack
	_release = hold_release if is_hold else tap_release
	_sustain_left = duration + (hold_extra if is_hold else tap_extra)


func _on_aim_started(_max_hold: float) -> void:
	_aiming = true
	_release = hold_release


func _on_aim_ended() -> void:
	_aiming = false
