extends ColorRect
class_name DashBar
## Dash bar under the crosshair. Only listens to signals, so movement can change freely.
## Signals it expects on `source` (connected by name, no class dependency):
##   dash_ready_changed(ready: bool)
##   dash_cooldown_started(duration: float)   game seconds
##   dash_aim_started(max_hold: float)        real seconds until the hold dash fires by itself
##   dash_aim_ended()
## Looks:  dim and filling = cooling down,  dim and full = waiting for a charge (in the air),
##         pop + bright = usable,  gold and draining = aiming a hold dash.

@export var source: Node                ## the node that emits the dash signals (PlayerMovement)
@export var pop_time := 0.25            ## seconds the pop flash lasts
@export var look_blend_speed := 20.0    ## how fast it switches between the dim and bright look
@export_range(0.0, 1.0) var hold_warning := 0.3  ## remaining hold below which the bar flashes
@export var idle_delay := 1.0           ## seconds of being ready before the bar fades back
@export_range(0.0, 1.0) var idle_alpha := 0.45
@export var fade_speed := 6.0

var _usable := true
var _cool_total := 0.0
var _cool_left := 0.0
var _aiming := false
var _aim_total := 1.0
var _aim_left := 0.0
var _pop := 0.0
var _look := 1.0                        # smoothed 0 (dim) .. 1 (bright)
var _idle_time := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	source.connect(&"dash_ready_changed", _on_ready_changed)
	source.connect(&"dash_cooldown_started", _on_cooldown_started)
	source.connect(&"dash_aim_started", _on_aim_started)
	source.connect(&"dash_aim_ended", _on_aim_ended)
	resized.connect(_sync_size)
	_sync_size()


func _process(delta: float) -> void:
	var real_dt := delta / maxf(Engine.time_scale, 0.0001)   # the hold slows time; the UI shouldn't
	_cool_left = maxf(_cool_left - delta, 0.0)              # cooldown runs on game time, like the dash
	if _aiming:
		_aim_left = maxf(_aim_left - real_dt, 0.0)

	var fill := 1.0
	if _aiming:
		fill = _aim_left / _aim_total                       # drains toward the auto-fire
	elif not _usable and _cool_left > 0.0:
		fill = 1.0 - _cool_left / _cool_total               # refilling

	_look = lerpf(_look, 1.0 if _usable else 0.0, 1.0 - exp(-look_blend_speed * real_dt))
	_pop = maxf(_pop - real_dt / pop_time, 0.0)
	var pulse := 0.0
	if _aiming and fill < hold_warning:
		pulse = 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.03)

	var mat := material as ShaderMaterial
	mat.set_shader_parameter("fill", fill)
	mat.set_shader_parameter("usable", _look)
	mat.set_shader_parameter("pop", _pop * _pop)
	mat.set_shader_parameter("hold", 1.0 if _aiming else 0.0)
	mat.set_shader_parameter("pulse", pulse)

	# Fade back a little while it just sits there ready, so it doesn't clutter the view.
	_idle_time = _idle_time + real_dt if _usable and not _aiming else 0.0
	var target_alpha := idle_alpha if _idle_time > idle_delay else 1.0
	modulate.a = move_toward(modulate.a, target_alpha, fade_speed * real_dt)


func _on_ready_changed(ready: bool) -> void:
	if ready and not _usable:
		_pop = 1.0
	_usable = ready


func _on_cooldown_started(duration: float) -> void:
	_cool_total = maxf(duration, 0.0001)
	_cool_left = duration


func _on_aim_started(max_hold: float) -> void:
	_aiming = true
	_aim_total = maxf(max_hold, 0.0001)
	_aim_left = max_hold


func _on_aim_ended() -> void:
	_aiming = false


func _sync_size() -> void:
	(material as ShaderMaterial).set_shader_parameter("rect_size", size)
