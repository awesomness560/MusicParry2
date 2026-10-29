extends MoveState
class_name GroundState
## On the floor. Below run speed: snap to full speed or to a stop. Above it: steer freely while the
## extra speed (momentum) fades. Also owns the ground jump and its forward propel.

@export_group("Run")
@export var accel_time := 0.06          ## seconds from standing to full run
@export var stop_time := 0.05           ## seconds from full run to standing

@export_group("Momentum")
@export var momentum_decay := 3.0       ## how fast speed above run fades while you keep moving
@export var release_decay := 12.0       ## how fast it fades when you let go of input
@export var turn_speed := 540.0         ## degrees per second you can turn while above run speed
@export var bhop_window := 0.1          ## seconds after landing where momentum doesn't fade

@export_group("Jump")
@export var boost_mult := 1.0           ## forward push on jump, in x run speed, when starting from standing
@export var chain_mult := 3.0           ## speed (x run) where the push has shrunk to nothing (or the cap, if lower)


func enter(_old: PlayerMovement.State) -> void:
	motor.landed_at = motor.time        # opens the bhop window, and unblocks walls
	motor.air_budget.refresh(&"landed")
	if motor.fall_speed > 0.0:          # a flat dash ending on the floor isn't a landing
		motor.landed.emit(motor.fall_speed)


func exit(_new: PlayerMovement.State) -> void:
	motor.left_floor_at = motor.time    # starts coyote time


func physics_update(delta: float) -> void:
	_move(motor.wish, delta)
	if motor.jump_buffered():
		jump()


func after_move() -> void:
	if not body.is_on_floor():
		motor.change_state(PlayerMovement.State.AIR)   # walked off a ledge


## Also used by the air state for coyote jumps.
func jump() -> void:
	motor.consume_jump()
	motor.change_state(PlayerMovement.State.AIR)
	motor.left_floor_at = -INF          # used up: no coyote jump after a real one
	body.velocity.y = motor.jump_velocity()
	_propel(motor.wish)
	motor.jumped.emit()


func _move(wish: Vector3, delta: float) -> void:
	var h := motor.horizontal()
	var speed := h.length()
	var run := motor.run_speed

	if speed <= run:
		motor.is_braking = false
		# Run: snap to full speed in the input direction, or to a stop.
		var t := accel_time if wish != Vector3.ZERO else stop_time
		motor.set_horizontal(h.move_toward(wish * run, run / t * delta))
		return

	# Momentum: split speed into run speed + excess. Steer the direction, fade the excess.
	var dir := h / speed
	var excess := speed - run
	var in_bhop := motor.in_bhop_window()
	motor.is_braking = motor.is_brake_input(dir, wish)

	if motor.is_braking:
		excess = motor.decay(excess, motor.brake_decay, delta)
	elif wish == Vector3.ZERO:
		if not in_bhop:
			excess = motor.decay(excess, release_decay, delta)   # let go: fade fast, then stop_time stops you
	else:
		dir = motor.turn_toward(dir, wish, deg_to_rad(turn_speed) * delta)
		if not in_bhop:
			excess = motor.decay(excess, momentum_decay, delta)

	motor.set_horizontal(dir * (run + excess))


## Forward push in the input direction. It shrinks as you get faster, reaching zero at
## chain_mult x run speed (or the speed cap, if that's lower), so jump chains level off.
func _propel(wish: Vector3) -> void:
	if wish == Vector3.ZERO:
		return                          # no input = straight up
	var limit := minf(chain_mult * motor.run_speed, motor.speed_cap())
	var falloff := clampf(1.0 - motor.horizontal_speed() / limit, 0.0, 1.0)
	body.velocity += wish * boost_mult * motor.run_speed * falloff
