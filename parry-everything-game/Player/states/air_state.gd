extends MoveState
class_name AirState
## In the air. Low speed: direct, snappy control for fighting. High speed: input turns your velocity
## instead of adding to it, so you carve without losing speed. Owns the double jump, and turns late
## jump presses into ground jumps or wall kicks (coyote time).

@export_group("Control")
@export var accel_time := 0.15          ## below run speed: seconds to reach run speed
@export var turn_snappy := 720.0        ## deg/s you can turn just above run speed
@export var turn_carve := 200.0         ## deg/s you can turn at full carve speed
@export var carve_full_mult := 2.0      ## at this many x run speed, turning is fully at turn_carve
@export var drag := 0.05                ## how fast speed above run fades. Almost nothing.

@export_group("Double Jump")
@export var double_jump_height := 2.2   ## metres gained from the moment you press it (at run speed)
@export_range(0.0, 1.0) var double_jump_redirect := 1.0  ## 1 = velocity points fully at your input, 0 = no turn


func physics_update(delta: float) -> void:
	_move(motor.wish, delta)
	if motor.jump_buffered():
		_jump()
	motor.apply_gravity(delta)


func after_move() -> void:
	if body.is_on_floor():
		motor.change_state(PlayerMovement.State.GROUND)
	else:
		motor.wallrun.try_grab()


func _jump() -> void:
	if motor.time - motor.left_floor_at <= motor.coyote_time:
		motor.ground.jump()                         # just left the floor
	elif motor.time - motor.left_wall_at <= motor.coyote_time:
		motor.wallrun.kick(motor.wallrun.normal)    # just left a wall
	elif not _landing_soon() and motor.air_budget.spend(&"double_jump"):
		_double_jump()
	# Otherwise the press stays buffered, so it becomes a ground jump on landing.


func _move(wish: Vector3, delta: float) -> void:
	var h := motor.horizontal()
	var speed := h.length()
	var run := motor.run_speed
	var control := motor.air_control_scale()   # 0 right after a kick or launch, back to 1 shortly after
	motor.carve_amount = 0.0

	if speed <= run:
		motor.is_braking = false
		# Low speed: direct control, like running. No input keeps your velocity (no air friction).
		if wish != Vector3.ZERO:
			motor.set_horizontal(h.move_toward(wish * run, run / accel_time * control * delta))
		return

	# High speed: input rotates your velocity instead of adding to it, so speed is kept.
	var dir := h / speed
	var excess := speed - run
	motor.is_braking = motor.is_brake_input(dir, wish) and control >= 1.0   # no accidental braking mid-launch

	if motor.is_braking:
		excess = motor.decay(excess, motor.brake_decay, delta)
	else:
		if wish != Vector3.ZERO:
			# The faster you go, the wider your turns.
			motor.carve_amount = clampf(inverse_lerp(run, carve_full_mult * run, speed), 0.0, 1.0)
			var turn_rate := lerpf(turn_snappy, turn_carve, motor.carve_amount) * control
			dir = motor.turn_toward(dir, wish, deg_to_rad(turn_rate) * delta)
		excess *= exp(-drag * delta)
		if excess < 0.05:
			excess = 0.0                # snap, so the low-speed rules take over next frame

	motor.set_horizontal(dir * (run + excess))


## Resets vertical speed and swings your horizontal speed toward your input. Your sharp air turn.
func _double_jump() -> void:
	motor.consume_jump()
	body.velocity.y = sqrt(2.0 * motor.rise_gravity() * double_jump_height)

	var wish := motor.wish
	if wish != Vector3.ZERO:
		var h := motor.horizontal()
		var speed := maxf(h.length(), motor.run_speed)   # never slower than run after a redirect
		var dir := h.normalized() if h.length() > 0.1 else wish
		var angle := dir.signed_angle_to(wish, Vector3.UP) * double_jump_redirect
		motor.set_horizontal(dir.rotated(Vector3.UP, angle) * speed)

	motor.double_jumped.emit()


## True if we're falling and will touch the floor within the jump buffer time,
## so a slightly early press becomes a bhop instead of wasting the double jump.
func _landing_soon() -> bool:
	if body.velocity.y >= 0.0:
		return false
	var col := KinematicCollision3D.new()
	if not body.test_move(body.global_transform, body.velocity * motor.jump_buffer, col):
		return false
	return col.get_normal().dot(Vector3.UP) >= cos(body.floor_max_angle)
