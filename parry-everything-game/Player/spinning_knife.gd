extends MeshInstance3D
class_name KnifeSpinVisual
## A single quad that draws the spinning knife and its smears. Hides the held knife while spinning.
## Place it on the hand at the point the knife spins around, lying in the spin plane.

@export var held_knife: Node3D               # the normal knife, hidden while spinning
@export var rotations_per_beat := 2.0        # spin speed locked to the song
@export var reverse := false
@export var spin_up_time := 0.12
@export var spin_down_time := 0.1
@export var test_key: Key = KEY_T            # testing only; set to None when the trick system drives it

var spinning := false
var _speed := 0.0                            # 0..1 ramp
var _angle := 0.0
var _mat: ShaderMaterial


func _ready() -> void:
	_mat = get_surface_override_material(0) as ShaderMaterial
	_set_rig_visible(false)


func start() -> void:
	spinning = true
	_set_rig_visible(true)


## instant = true snaps straight back to the held knife (for cancelling into a parry).
func stop(instant := false) -> void:
	spinning = false
	if instant:
		_speed = 0.0
		_set_rig_visible(false)


func _process(delta: float) -> void:
	var target := 1.0 if spinning else 0.0
	var ramp := spin_up_time if spinning else spin_down_time
	_speed = move_toward(_speed, target, delta / maxf(ramp, 0.001))
	if not spinning and _speed <= 0.0:
		if visible:
			_set_rig_visible(false)
		return

	var dir := -1.0 if reverse else 1.0
	var rate := TAU * rotations_per_beat / Conductor.seconds_per_beat()
	_angle = fposmod(_angle + rate * _speed * delta * dir, TAU)

	if _mat:
		_mat.set_shader_parameter("speed", _speed)
		_mat.set_shader_parameter("intensity", minf(_speed * 3.0, 1.0))
		_mat.set_shader_parameter("spin_angle", _angle)
		_mat.set_shader_parameter("direction", dir)


func _set_rig_visible(on: bool) -> void:
	visible = on
	if held_knife:
		held_knife.visible = not on
	if not on:
		_angle = 0.0


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if test_key == KEY_NONE or key == null or not key.pressed or key.echo:
		return
	if key.keycode == test_key:
		if spinning:
			stop()
		else:
			start()
