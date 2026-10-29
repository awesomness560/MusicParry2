extends Label
class_name MovementDebug
## Live movement numbers on screen. Press F3 to show or hide.

@export var movement: PlayerMovement
@export var peak_hold := 1.5            ## seconds the peak speed stays on screen
@export var bar_steps_per_run := 4      ## bar characters per 1x run speed
@export var toggle_key := KEY_F3

var _peak := 0.0
var _peak_left := 0.0


func _ready() -> void:
	add_theme_font_size_override("font_size", 18)
	add_theme_constant_override("outline_size", 6)
	add_theme_color_override("font_outline_color", Color.BLACK)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == toggle_key:
		visible = not visible


func _physics_process(delta: float) -> void:
	if not visible or movement == null:
		return

	var body := movement.body
	var run := movement.run_speed
	var speed := movement.horizontal_speed()
	var mult := speed / run

	# Peak: jumps up instantly, holds for a moment, then follows the current speed again.
	_peak_left -= delta
	if speed >= _peak or _peak_left <= 0.0:
		_peak = speed
		_peak_left = peak_hold

	var flags := []
	if movement.in_bhop_window():
		flags.append("BHOP")
	if movement.is_braking:
		flags.append("BRAKE")
	if movement.is_over_cap:
		flags.append("OVER CAP")

	var lines := [
		"SPEED   %5.1f m/s   %.2fx run" % [speed, mult],
		"|".repeat(roundi(mult * bar_steps_per_run)),
		"PEAK    %5.1f m/s   %.2fx" % [_peak, _peak / run],
		"EXCESS  %5.1f m/s" % maxf(speed - run, 0.0),
		"CAP     %5.1f m/s   %.2fx   rank %s" % [
			movement.speed_cap(), movement.speed_cap() / run, Style.current_rank()["name"]],
		"VERT    %+5.1f m/s   gravity x%.2f" % [body.velocity.y, movement.gravity_scale()],
		"CARVE   %.2f   control x%.2f" % [movement.carve_amount, movement.air_control_scale()],
		"BUDGET  dj %d   dash %d   launch %d" % [
			movement.air_budget.left(&"double_jump"),
			movement.air_budget.left(&"dash"),
			movement.air_budget.left(&"launch")],
		"STATE   %s   %s" % [movement.state_name(), " ".join(flags)],
	]
	text = "\n".join(lines)

	# White at run speed, turning orange as momentum builds toward 3x.
	modulate = Color.WHITE.lerp(Color(1.0, 0.6, 0.2), clampf((mult - 1.0) / 2.0, 0.0, 1.0))
