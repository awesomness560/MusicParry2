extends Control
class_name RankDisplay
## Shows the style rank letter. On a change, the old letter pops and bursts into shards
## (scaled by intensity) and the new one slams in.
## Controlled with set_rank(), set_rank_instant(), set_color(), set_warning().

@export var letter: Label                 # the big rank letter (child of this node, centre-aligned)
@export var subtitle: Label               # optional rank name under it
@export var shatter_shader: Shader        # rank_shatter.gdshader
@export var shatter_size := Vector2(360, 360)   # px size of the burst area, centred on the letter

@export_group("Slam")
@export var slam_time := 0.18
@export var slam_scale_low := 1.6
@export var slam_scale_high := 2.6
@export var shake_low := 2.0
@export var shake_high := 9.0
@export var pop_time := 0.1

@export_group("Warning")
@export var flicker_depth := 0.75         # how far the letter dims when flickering at full warning

var _ghost: Label
var _shatter: ColorRect
var _shatter_mat: ShaderMaterial
var _shatter_t := 1.0
var _shatter_dur := 0.5
var _ghost_t := 1.0
var _ghost_up := true
var _slam_t := 1.0
var _slam_from := 1.0
var _shake := 0.0
var _color := Color.WHITE
var _letter_home := Vector2.ZERO
var _warning := 0.0
var _flick_timer := 0.0
var _flick_off := false


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	_letter_home = letter.position
	_make_settings_unique(letter)
	if subtitle:
		_make_settings_unique(subtitle)
	_color = _get_label_color(letter)

	_ghost = letter.duplicate() as Label
	_make_settings_unique(_ghost)
	_ghost.visible = false
	add_child(_ghost)
	move_child(_ghost, letter.get_index())

	_shatter = ColorRect.new()
	_shatter.mouse_filter = MOUSE_FILTER_IGNORE
	_shatter.visible = false
	_shatter_mat = ShaderMaterial.new()
	_shatter_mat.shader = shatter_shader
	_shatter.material = _shatter_mat
	add_child(_shatter)
	move_child(_shatter, letter.get_index())


# ---------------------------------------------------------------- public API

## Change the rank with effects. intensity 0..1 scales the burst and slam.
## rank_up = false makes the old letter crumble and drop instead of exploding.
func set_rank(text: String, color: Color, subtitle_text := "", intensity := 0.5, rank_up := true) -> void:
	intensity = clampf(intensity, 0.0, 1.0)

	if not letter.text.is_empty():
		_ghost.text = letter.text
		_set_label_color(_ghost, _color)
		_ghost.position = _letter_home
		_ghost.size = letter.size
		_ghost.pivot_offset = letter.size * 0.5
		_ghost.scale = Vector2.ONE
		_ghost.visible = true
		_ghost_t = 0.0
		_ghost_up = rank_up
		_start_shatter(intensity, rank_up)

	_apply(text, color, subtitle_text)
	_slam_t = 0.0
	if rank_up:
		_slam_from = lerpf(slam_scale_low, slam_scale_high, intensity)
		_shake = lerpf(shake_low, shake_high, intensity)
	else:
		_slam_from = 0.8
		_shake = 0.0


## Change the rank with no effects (e.g. at the start of a level).
func set_rank_instant(text: String, color: Color, subtitle_text := "") -> void:
	_apply(text, color, subtitle_text)


## Recolour without changing the rank (used for the SSS colour shift).
func set_color(color: Color) -> void:
	_color = color
	_set_label_color(letter, color)
	if subtitle:
		_set_label_color(subtitle, color)


## 0 = off, 1 = about to rank down. The letter flickers harder the closer it gets.
func set_warning(strength: float) -> void:
	_warning = clampf(strength, 0.0, 1.0)


# ---------------------------------------------------------------- internals

func _apply(text: String, color: Color, subtitle_text: String) -> void:
	letter.text = text
	if subtitle:
		subtitle.text = subtitle_text
	set_color(color)


func _start_shatter(intensity: float, rank_up: bool) -> void:
	_shatter.size = shatter_size
	_shatter.position = _letter_home + letter.size * 0.5 - shatter_size * 0.5
	var m := _shatter_mat
	m.set_shader_parameter("shard_color", _color)
	m.set_shader_parameter("seed", randf() * 100.0)
	m.set_shader_parameter("progress", 0.0)
	if rank_up:
		m.set_shader_parameter("count", int(round(lerpf(10.0, 48.0, intensity))))
		m.set_shader_parameter("force", lerpf(0.5, 1.0, intensity))
		m.set_shader_parameter("spin", lerpf(2.5, 7.0, intensity))
		m.set_shader_parameter("gravity", 0.25)
		m.set_shader_parameter("flash", lerpf(0.4, 0.9, intensity))
		_shatter_dur = lerpf(0.4, 0.7, intensity)
	else:
		m.set_shader_parameter("count", 10)
		m.set_shader_parameter("force", 0.15)
		m.set_shader_parameter("spin", 1.5)
		m.set_shader_parameter("gravity", 0.9)
		m.set_shader_parameter("flash", 0.0)
		_shatter_dur = 0.5
	_shatter_t = 0.0
	_shatter.visible = true


func _make_settings_unique(l: Label) -> void:
	if l.label_settings:
		l.label_settings = l.label_settings.duplicate()


func _get_label_color(l: Label) -> Color:
	if l.label_settings:
		return l.label_settings.font_color
	return l.get_theme_color("font_color")


func _set_label_color(l: Label, color: Color) -> void:
	if l.label_settings:
		l.label_settings.font_color = color
	else:
		l.add_theme_color_override("font_color", color)


func _process(delta: float) -> void:
	if _shatter.visible:
		_shatter_t += delta / _shatter_dur
		_shatter_mat.set_shader_parameter("progress", minf(_shatter_t, 1.0))
		if _shatter_t >= 1.0:
			_shatter.visible = false

	if _ghost.visible:
		_ghost_t = minf(_ghost_t + delta / pop_time, 1.0)
		if _ghost_up:
			_ghost.scale = Vector2.ONE * lerpf(1.0, 1.35, _ghost_t)
		else:
			_ghost.position = _letter_home + Vector2(0, 20.0 * _ghost_t)
		_ghost.modulate.a = 1.0 - _ghost_t
		if _ghost_t >= 1.0:
			_ghost.visible = false

	var slam := 1.0
	var alpha := 1.0
	if _slam_t < 1.0:
		_slam_t = minf(_slam_t + delta / slam_time, 1.0)
		slam = lerpf(1.0, _slam_from, pow(1.0 - _slam_t, 3.0))
		alpha = clampf(_slam_t * 2.5, 0.0, 1.0)

	var offset := Vector2.ZERO
	if _shake > 0.0:
		offset = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * _shake * (1.0 - _slam_t)
		if _slam_t >= 1.0:
			_shake = 0.0

	# brink flicker: irregular dips, faster and deeper as the warning grows
	if _warning > 0.0:
		_flick_timer -= delta
		if _flick_timer <= 0.0:
			_flick_off = not _flick_off and randf() < 0.35 + 0.5 * _warning
			_flick_timer = randf_range(0.03, 0.12) * (1.5 - _warning)
		if _flick_off:
			alpha *= 1.0 - flicker_depth * _warning
	else:
		_flick_off = false

	letter.pivot_offset = letter.size * 0.5
	letter.scale = Vector2.ONE * slam
	letter.position = _letter_home + offset
	letter.modulate.a = alpha
	if subtitle:
		subtitle.modulate.a = alpha
