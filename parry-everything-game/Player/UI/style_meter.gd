extends ColorRect
class_name StyleMeterBar
## Drives style_meter.gdshader: spring-eased fill, white gain segment, spark, brink warning.
## Controlled with set_value(), set_value_instant(), set_fill_color(), set_warning().

@export_range(0.0, 1.0) var value := 0.0: set = set_value   # target; the bar springs toward it

@export_group("Spring")
@export var stiffness := 320.0         # higher = snappier
@export var damping := 20.0            # lower = more overshoot (20 gives a small kick past and back)

@export_group("Gain trail")
@export var show_gain_trail := true    # white "just gained" segment before the bar catches up
@export var trail_delay := 0.3
@export var trail_speed := 1.5
@export var spark_fade := 0.25

@export_group("Warning")
@export var warning_rate := 6.0        # edge pulses per second

var _shown := 0.0
var _vel := 0.0
var _trail := 0.0
var _trail_wait := 0.0
var _spark := 0.0
var _warning := 0.0
var _warn_phase := 0.0
var _mat: ShaderMaterial


func _ready() -> void:
	_mat = material as ShaderMaterial
	mouse_filter = MOUSE_FILTER_IGNORE
	_shown = value
	_trail = value
	resized.connect(_update_size)
	_update_size()


func set_value(v: float) -> void:
	v = clampf(v, 0.0, 1.0)
	if v > value + 0.0001:
		_spark = 1.0
		_trail_wait = trail_delay
	value = v


## Jump straight to a value with no spring or trail (e.g. resetting after a rank change).
func set_value_instant(v: float) -> void:
	value = clampf(v, 0.0, 1.0)
	_shown = value
	_vel = 0.0
	_trail = value
	_trail_wait = 0.0


func set_fill_color(c: Color) -> void:
	if _mat:
		_mat.set_shader_parameter("fill_color", c)


## 0 = off, 1 = about to rank down.
func set_warning(strength: float) -> void:
	_warning = clampf(strength, 0.0, 1.0)


func _update_size() -> void:
	if _mat:
		_mat.set_shader_parameter("rect_size", size)


func _process(delta: float) -> void:
	# damped spring toward the target, in small steps so lag spikes can't make it explode
	var steps := maxi(ceili(delta / (1.0 / 120.0)), 1)
	var dt := delta / steps
	for i in steps:
		_vel += (stiffness * (value - _shown) - damping * _vel) * dt
		_shown += _vel * dt
	var shown := clampf(_shown, 0.0, 1.0)

	if not show_gain_trail:
		_trail = shown
	elif _trail_wait > 0.0:
		_trail_wait -= delta
	else:
		_trail = move_toward(_trail, shown, trail_speed * delta)
	_trail = minf(_trail, shown)

	if _trail < shown - 0.001:
		_spark = 1.0
	else:
		_spark = maxf(_spark - delta / spark_fade, 0.0)

	_warn_phase += delta * warning_rate * TAU
	var w := _warning * (0.5 + 0.5 * sin(_warn_phase))

	if _mat:
		_mat.set_shader_parameter("fill", shown)
		_mat.set_shader_parameter("trail", _trail)
		_mat.set_shader_parameter("spark", _spark)
		_mat.set_shader_parameter("warning", w)
