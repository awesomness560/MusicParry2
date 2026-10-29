extends MoveState
class_name WallrunState
## Wallrun: keeps your entry speed, gravity starts gentle and grows, round pillars make you orbit.
## Wall kick: a hefty push away and up, weighted toward where you look.

@export_group("Grab")
@export var entry_max_angle := 40.0  ## degrees: your movement must hit the wall at most this steeply (0 = parallel)
@export var entry_look_angle := 35.0  ## degrees: you can't grab while looking into the wall more than this
@export var entry_min_speed_mult := 0.6  ## minimum horizontal speed to grab, in x run speed
@export var entry_up_max := 4.0  ## upward speed kept when grabbing (falling is caught to 0)
@export var regrab_plane_tolerance := 0.5  ## metres: a wall facing the same way only counts as the wall you left if it's this close to its plane
@export var regrab_radius := 4.0  ## metres: ...and this close along it to where you left (height ignored)
@export var chain_window := 1.0  ## seconds after leaving a wall where the next grab uses the chain limits
@export var chain_max_angle := 75.0  ## approach limit when chaining (you kick toward the next wall, so you hit it steeper)
@export var chain_look_angle := 80.0  ## look limit when chaining (you're usually looking at the wall you're heading for)

@export_group("Run")
@export var min_speed_mult := 1.2  ## wallrun speed is never below this many x run speed
@export var gravity_start := 3.0  ## gravity when the wallrun starts (gentle)
@export var gravity_end := 40.0  ## gravity once gravity_ramp has passed (strong)
@export var gravity_ramp := 1.2  ## seconds for gravity to grow from start to end
@export var stick := 2.0  ## m/s pushed into the wall so you stay in contact
@export var release_dot := 0.7  ## input pointing this much away from the wall lets go (0..1)
@export var release_push := 3.0  ## m/s outward when you let go
@export var grace := 0.1  ## seconds without a wall before the wallrun ends
@export var probe_length := 1.0  ## how far the wall check reaches from the body (radius + margin)
@export var probe_offset := Vector3.ZERO  ## raise this if the body's origin is at its feet (aim for mid-body)

@export_group("Kick")
@export var kick_mult := 1.4  ## push in x run speed, added on top of your current speed
@export var kick_height := 2.0  ## metres of upward kick
@export_range(0.0, 1.0) var kick_look_bias := 0.6  ## 0 = straight out from the wall, 1 = fully where you look
@export_range(0.0, 1.0) var kick_min_out := 0.5  ## the kick always points at least this much away from the wall
@export var kick_control_time := 0.35  ## seconds after a kick for air control to fade back in

## The current wall (or the last one, after leaving it): flat, pointing away from the wall.
var normal := Vector3.ZERO
## Why the last wall touch didn't become a wallrun ("" after a successful grab). For the debug label.
var last_grab_fail := ""

var _dir := Vector3.ZERO  # run direction along the wall
var _speed := 0.0  # wallrun speed, kept from entry
var _started_at := 0.0  # drives the growing gravity
var _seen_at := 0.0  # last time the wall check found the wall
var _blocked_normal := Vector3.ZERO  # the wall you last left can't be grabbed again...
var _blocked_pos := Vector3.ZERO  # ...near where you left it...
var _blocked_at := -INF  # ...until you land after this time


## Called by the air state after each move: grabs the wall we touched, if the conditions are right.
func try_grab() -> void:
	if not body.is_on_wall():
		return
	var n := motor.flat(body.get_wall_normal())
	if n == Vector3.ZERO:
		return
	if _is_blocked(n):
		last_grab_fail = "same wall"
		return
	if motor.wish.dot(n) > release_dot:
		last_grab_fail = "holding away"
		return

	# Coming straight from another wall: you meant it, so the angle limits are looser.
	var chaining := _blocked_at > motor.landed_at and motor.time - _blocked_at <= chain_window
	var max_angle := chain_max_angle if chaining else entry_max_angle
	var look_angle := chain_look_angle if chaining else entry_look_angle

	# The velocity from before the slide: the slide has already removed the part going into the wall.
	var h := Vector3(motor.pre_move_velocity.x, 0.0, motor.pre_move_velocity.z)
	var speed := h.length()
	if speed < entry_min_speed_mult * motor.run_speed:
		last_grab_fail = "too slow"
		return
	var approach := _angle_into(h / speed, n)
	if approach > max_angle:
		last_grab_fail = "too head-on (%d°)" % approach
		return
	var look := _angle_into(motor.flat_look_direction(), n)
	if look > look_angle:
		last_grab_fail = "looking into it (%d°)" % look
		return
	var dir := _along(h, n)
	if dir == Vector3.ZERO:
		last_grab_fail = "nothing to run along"
		return

	last_grab_fail = ""
	normal = n
	_dir = dir
	_speed = maxf(speed, min_speed_mult * motor.run_speed)
	_started_at = motor.time
	_seen_at = motor.time
	body.velocity.y = clampf(body.velocity.y, 0.0, entry_up_max)
	motor.change_state(PlayerMovement.State.WALLRUN)
	motor.air_budget.refresh(&"wall")


func exit(_new: PlayerMovement.State) -> void:
	motor.left_wall_at = motor.time  # starts wall coyote time
	_block(normal)


func physics_update(delta: float) -> void:
	# Re-find the wall every frame. On a round pillar the normal keeps turning, which makes you orbit.
	var hit := _probe(normal)
	if not hit.is_empty():
		_seen_at = motor.time
		normal = motor.flat(hit.normal)

	# Input exits
	if motor.jump_buffered():
		kick(normal)
		return
	var wish := motor.wish
	if wish != Vector3.ZERO and wish.dot(normal) > release_dot:
		motor.set_horizontal(_dir * _speed + normal * release_push)
		motor.change_state(PlayerMovement.State.AIR)
		return

	# Keep the run direction flat along the (possibly turned) wall.
	var along := _along(_dir, normal)
	if along != Vector3.ZERO:
		_dir = along

	# Pulling back against the run direction brakes, down to the minimum wallrun speed.
	var floor_speed := min_speed_mult * motor.run_speed
	motor.is_braking = wish.dot(_dir) < -0.5
	if motor.is_braking and _speed > floor_speed:
		_speed = floor_speed + motor.decay(_speed - floor_speed, motor.brake_decay, delta)
	_speed = motor.limit_speed(_speed, delta)

	motor.set_horizontal(_dir * _speed - normal * stick)

	# Gravity starts gentle and grows (squared: gentle for a while, then ramps quickly).
	var t := clampf((motor.time - _started_at) / gravity_ramp, 0.0, 1.0)
	var g := lerpf(gravity_start, gravity_end, t * t)
	body.velocity.y = maxf(body.velocity.y - g * delta, -motor.max_fall_speed)


func after_move() -> void:
	if body.is_on_floor():
		motor.change_state(PlayerMovement.State.GROUND)
	elif motor.time - _seen_at > grace:
		motor.change_state(PlayerMovement.State.AIR)  # ran off the end of the wall


## Kicks off a wall. Also used by the air state for coyote kicks.
func kick(n: Vector3) -> void:
	motor.consume_jump()

	# Looking into the wall? Bounce the look direction off it like a mirror,
	# so looking in at an angle kicks you out at that same angle.
	var look := motor.flat_look_direction()
	if look.dot(n) < 0.0:
		look -= 2.0 * look.dot(n) * n
	var dir := n.lerp(look, kick_look_bias).normalized()
	var out := dir.dot(n)
	if out < kick_min_out:
		dir = (dir + n * (kick_min_out - out)).normalized()  # never kick into the wall

	var h := motor.horizontal()
	h -= n * minf(h.dot(n), 0.0)  # drop any speed pointing into the wall (the stick)
	motor.set_horizontal(h + dir * kick_mult * motor.run_speed)
	body.velocity.y = sqrt(2.0 * motor.rise_gravity() * kick_height)

	motor.change_state(PlayerMovement.State.AIR)
	motor.left_wall_at = -INF  # used up: no coyote kick after a real one
	motor.left_floor_at = -INF
	_block(n)
	motor.suppress_air_control(kick_control_time)  # let the kick carry you before input can steer
	motor.wall_kicked.emit(dir)


func _block(n: Vector3) -> void:
	_blocked_normal = n
	_blocked_pos = body.global_position
	_blocked_at = motor.time


## The spot you last left is blocked until you land: a wall facing the same way (within ~45°),
## in the same plane, and near where you left it. Other walls on the same side are free to grab.
## Uses the body's position: while wallrunning you're always about one radius from the wall,
## so comparing where you are now with where you left measures the gap between the two walls.
func _is_blocked(n: Vector3) -> bool:
	if _blocked_at <= motor.landed_at or n.dot(_blocked_normal) <= 0.7:
		return false
	var offset := body.global_position - _blocked_pos
	offset.y = 0.0  # height doesn't matter: climbing stays blocked
	var off_plane := absf(offset.dot(_blocked_normal))  # staggered walls are in different planes
	var along := (offset - _blocked_normal * offset.dot(_blocked_normal)).length()
	return off_plane < regrab_plane_tolerance and along < regrab_radius


## Degrees a direction points into the wall: 0 = along or away from it, 90 = straight in.
func _angle_into(dir: Vector3, n: Vector3) -> float:
	return rad_to_deg(asin(clampf(-dir.dot(n), 0.0, 1.0)))


## The part of v that runs along the wall, flat and normalized. ZERO if there's almost none.
func _along(v: Vector3, n: Vector3) -> Vector3:
	var a := v - n * v.dot(n)
	a.y = 0.0
	return a.normalized() if a.length() >= 0.1 else Vector3.ZERO


## Raycasts from mid-body toward the wall. Returns {} if there's no runnable wall.
func _probe(n: Vector3) -> Dictionary:
	var from := body.global_position + probe_offset
	var query := PhysicsRayQueryParameters3D.create(from, from - n * probe_length)
	query.exclude = [body.get_rid()]
	query.collision_mask = body.collision_mask
	var hit := body.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty() or absf(hit.normal.y) >= cos(body.floor_max_angle):
		return {}  # nothing there, or it's a floor or ceiling
	return hit
