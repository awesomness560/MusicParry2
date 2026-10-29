extends Node3D
## Autoload "DamageNumbers". Spawns floating, camera-facing damage numbers in the 3D world,
## coloured by attack outcome, animates them and frees them.
##
## DamageNumbers.spawn(position, 25, result)

@export_group("Text")
@export var font: Font
@export var font_size := 64
@export var outline_size := 12
@export var outline_color := Color(0, 0, 0, 0.85)
@export var pixel_size := 0.005  # world size per font pixel
@export var fixed_size := false  # true = same size on screen at any distance
@export var always_on_top := true  # draw through walls and enemies
@export var max_numbers := 40  # oldest are removed past this

@export_group("Colours")
@export var default_color := Color.WHITE
@export var perfect_color := Color(1.0, 0.72, 0.3)
@export var parry_color := Color(1.0, 1.0, 1.0)
@export var hit_color := Color(1.0, 0.35, 0.3)

@export_group("Animation")
@export var lifetime := 0.8
@export var rise := 0.8  # metres it floats up
@export var drift := 0.35  # metres it drifts sideways (camera left/right)
@export var spread := 0.15  # random offset at spawn so numbers don't stack exactly
@export var pop_scale := 1.6  # starts this big and snaps down
@export var pop_time := 0.12
@export var perfect_scale := 1.4  # perfect parries are bigger
@export var fade_start := 0.6  # fraction of the lifetime before fading begins


class Num:
	var label: Label3D
	var origin := Vector3.ZERO
	var drift_dir := Vector3.ZERO
	var color := Color.WHITE
	var size := 1.0
	var age := 0.0


var _nums: Array[Num] = []

# ---------------------------------------------------------------- public API


## Spawn a number at a world position.
## result picks the colour and size (null = default). color overrides the colour if given.
## scale multiplies the size (e.g. for big hits).
func spawn_number(
	world_pos: Vector3,
	amount: float,
	result: AttackResult = null,
	color: Variant = null,
	scale_mult := 1.0
) -> void:
	var n := Num.new()
	n.color = color if color is Color else _color_for(result)
	n.size = scale_mult
	if result and result.outcome == AttackResult.Outcome.PERFECT_PARRY:
		n.size *= perfect_scale

	var cam := get_viewport().get_camera_3d()
	var side := cam.global_basis.x if cam else Vector3.RIGHT
	n.drift_dir = side * randf_range(-1.0, 1.0)
	n.origin = (
		world_pos + Vector3(randf_range(-1, 1), randf_range(-0.5, 1), randf_range(-1, 1)) * spread
	)

	n.label = _make_label(_format(amount))
	add_child(n.label)
	n.label.global_position = n.origin
	_nums.append(n)

	while _nums.size() > max_numbers:
		_nums[0].label.queue_free()
		_nums.remove_at(0)


func clear() -> void:
	for n in _nums:
		n.label.queue_free()
	_nums.clear()


# ---------------------------------------------------------------- per frame


func _process(delta: float) -> void:
	for i in range(_nums.size() - 1, -1, -1):
		var n := _nums[i]
		n.age += delta
		var t := n.age / lifetime
		if t >= 1.0:
			n.label.queue_free()
			_nums.remove_at(i)
			continue

		var move := 1.0 - pow(1.0 - t, 3.0)  # fast start, slowing down
		n.label.global_position = n.origin + Vector3.UP * rise * move + n.drift_dir * drift * move

		var s := 1.0
		if n.age < pop_time:
			s = lerpf(pop_scale, 1.0, 1.0 - pow(1.0 - n.age / pop_time, 3.0))
		n.label.scale = Vector3.ONE * s * n.size

		var a := 1.0 - smoothstep(fade_start, 1.0, t)
		n.label.modulate = Color(n.color, n.color.a * a)
		n.label.outline_modulate = Color(outline_color, outline_color.a * a)


# ---------------------------------------------------------------- helpers


func _make_label(text: String) -> Label3D:
	var l := Label3D.new()
	l.text = text
	if font:
		l.font = font
	l.font_size = font_size
	l.outline_size = outline_size
	l.outline_modulate = outline_color
	l.pixel_size = pixel_size
	l.fixed_size = fixed_size
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = always_on_top
	l.shaded = false
	l.double_sided = true
	l.render_priority = 10  # in front of other transparent effects
	l.outline_render_priority = 9
	return l


func _color_for(result: AttackResult) -> Color:
	if result == null:
		return default_color
	match result.outcome:
		AttackResult.Outcome.PERFECT_PARRY:
			return perfect_color
		AttackResult.Outcome.PARRY:
			return parry_color
		AttackResult.Outcome.HIT:
			return hit_color
	return default_color


func _format(amount: float) -> String:
	if is_equal_approx(amount, roundf(amount)):
		return str(roundi(amount))
	return "%.1f" % amount
