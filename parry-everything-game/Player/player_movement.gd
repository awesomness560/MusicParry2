extends Node
class_name PlayerMovement
## The movement motor. Owns the body's velocity, the state machine and the rules every state shares
## (gravity, momentum decay, input timing). Each state is a child node with its own script and settings:
##   Ground   run, momentum on the floor, ground jump
##   Air      air control and carving, double jump, coyote jumps and kicks
##   Dash     tap dash and hold dash (DASH and DASH_AIM)
##   Wallrun  wallrun and wall kick
## Anything outside movement that wants to push the player uses apply_force() or add_acceleration().

enum State { GROUND, AIR, DASH, WALLRUN, DASH_AIM }
enum Force { ADD, MAX, REDIRECT, SET }

signal state_changed(new_state: State, old_state: State)
signal force_applied(force: Vector3, mode: Force, source: StringName)
signal tilt(inputVector: Vector2)
signal jumped
signal double_jumped
signal dashed(direction: Vector3, is_hold: bool, duration: float)
signal dash_aim_started(max_hold: float)   # hold dash began: real seconds until it fires by itself
signal dash_aim_ended                      # aim over (dash fired, or knocked out of it)
signal dash_ready_changed(ready: bool)     # dash became usable or unusable
signal dash_cooldown_started(duration: float)
signal wall_kicked(direction: Vector3)
signal landed(impact_speed: float)

@export_group("References")
@export var body: Player
@export var camera_controller: CameraController
@export var defense: PlayerDefense
@export var air_budget: AirBudget
@export var vignetteColorRect: ColorRect

@export_group("States")
@export var ground: GroundState
@export var air: AirState
@export var dash: DashState
@export var wallrun: WallrunState

@export_group("Speed")
@export var run_speed := 9.0            ## m/s. Everything else is tuned around this.
@export var tail_decay := 6.0           ## m/s per second always removed when momentum fades, so the fade actually ends
@export var brake_angle := 120.0        ## input at least this far from your velocity counts as braking
@export var brake_decay := 15.0         ## how fast speed above run fades while braking

@export_group("Speed Cap")
## Soft cap per style rank (D, C, B, A, S, SS, SSS), in x run speed.
@export var rank_caps: Array[float] = [3.0, 3.5, 4.0, 4.5, 5.5, 6.5, 7.5]
@export var over_cap_decay := 4.0       ## how fast speed above the cap fades (on top of tail_decay)

@export_group("Gravity")
@export var jump_height := 2.2          ## metres. With time_to_apex, this sets gravity and jump speed.
@export var time_to_apex := 0.32        ## seconds to reach the top of a jump
@export var fall_gravity_mult := 1.8    ## fall faster than you rise
@export var apex_speed := 1.5           ## vertical speed below this counts as the apex
@export var apex_gravity_mult := 0.5    ## gravity multiplier at the apex, for the hang
@export var max_fall_speed := 50.0
@export var speed_gravity_mult := 0.55      ## gravity multiplier once you're fast (see below)
@export var speed_gravity_full_mult := 3.0  ## at this many x run speed, gravity is fully at speed_gravity_mult

@export_group("Input Timing")
@export var coyote_time := 0.1          ## seconds after leaving a floor or wall where jump still counts
@export var jump_buffer := 0.12         ## seconds a jump press is remembered

# ---- Read-only for other scripts (debug label, camera, style).
var state := State.GROUND
var is_braking := false
var carve_amount := 0.0                 # 0 = snappy air turning, 1 = full carve
var is_over_cap := false                # true while speed above the cap is fading

# ---- Shared with the states. Times are readings of `time`; -INF means "never" or "used up".
var time := 0.0                         # movement clock: seconds of physics time
var input := Vector2.ZERO               # raw movement input this frame
var wish := Vector3.ZERO                # input as a flat, camera-relative world direction
var fall_speed := 0.0                   # downward speed just before this frame's move
var pre_move_velocity := Vector3.ZERO   # velocity before this frame's move (the slide removes the part into walls)
var landed_at := -INF                   # bhop window
var left_floor_at := -INF               # coyote jump
var left_wall_at := -INF                # coyote wall kick
var jump_pressed_at := -INF             # jump buffer

var _states := {}
var _accel := Vector3.ZERO              # continuous acceleration collected this frame
var _control_lock_time := 0.0
var _control_lock_until := -INF
var _last_parry_beat := -1              # two attacks on one beat send two parries; only react once


func _ready() -> void:
	_states = { State.GROUND: ground, State.AIR: air, State.DASH: dash, State.WALLRUN: wallrun,
			State.DASH_AIM: dash }      # one node handles both dash states
	for s in _states.values():
		s.motor = self
		s.body = body
	defense.parry_succeeded.connect(_on_parry_succeeded)


func _physics_process(delta: float) -> void:
	time += delta
	_read_input()
	if Input.is_action_just_pressed("jump"):
		jump_pressed_at = time
	dash.handle_input()

	# 1. The current state changes velocity: input, steering, gravity, jumps.
	_states[state].physics_update(delta)
	_apply_speed_cap(delta)
	body.velocity += _accel * delta     # wind zones and other continuous pushes
	_accel = Vector3.ZERO

	# 2. Move.
	fall_speed = -body.velocity.y       # move_and_slide zeroes this on landing, so keep a copy
	pre_move_velocity = body.velocity
	body.move_and_slide()

	# 3. The state reacts to what the move did: landed, touched a wall, ran out of time.
	_states[state].after_move()

	if vignetteColorRect:
		vignetteColorRect.visible = body.velocity.y < 0.0


## Every state change goes through here: exit the old state, enter the new one.
func change_state(new_state: State) -> void:
	if new_state == state:
		return
	var old := state
	_states[old].exit(new_state)
	state = new_state
	is_braking = false
	carve_amount = 0.0
	_states[new_state].enter(old)
	state_changed.emit(new_state, old)


# ================================================================ speed cap

## The soft cap in m/s, from the current style rank.
func speed_cap() -> float:
	if rank_caps.is_empty():
		return INF
	return rank_caps[clampi(Style.rank, 0, rank_caps.size() - 1)] * run_speed


## Speed above the cap fades instead of being cut off. Returns the new speed.
## The motor uses this on the body; the wallrun uses it on its own stored speed.
func limit_speed(speed: float, delta: float) -> float:
	var cap := speed_cap()
	is_over_cap = speed > cap
	if not is_over_cap:
		return speed
	return cap + decay(speed - cap, over_cap_decay, delta)


func _apply_speed_cap(delta: float) -> void:
	match state:
		State.GROUND, State.AIR:
			var h := horizontal()
			var speed := h.length()
			if speed > 0.0:
				set_horizontal(h * (limit_speed(speed, delta) / speed))
		State.DASH, State.DASH_AIM:
			is_over_cap = false         # the zip is meant to be fast; its exit gets capped afterwards
		# WALLRUN caps its own speed, since it sets velocity from it every frame.


# ================================================================ force API

## The one door for pushes from outside the movement code: explosions, tricks, launches, knockback.
##   ADD       adds the force to your velocity (explosions, knockback)
##   MAX       your speed along the force becomes at least its strength; never slows you (boosts)
##   REDIRECT  keeps your speed (or the force's strength, if higher) but points it along the force
##   SET       replaces your velocity outright (warps, scripted launches)
## source: a tag like &"explosion", sent out in force_applied for style, sound and camera.
## control_lock: seconds for air control to fade back in, so input can't steer the push away at once.
func apply_force(force: Vector3, mode := Force.ADD, source := &"", control_lock := 0.0) -> void:
	if force == Vector3.ZERO and mode != Force.SET:
		return
	var v := body.velocity
	match mode:
		Force.ADD:
			v += force
		Force.MAX:
			var dir := force.normalized()
			v += dir * maxf(force.length() - v.dot(dir), 0.0)
		Force.REDIRECT:
			v = force.normalized() * maxf(v.length(), force.length())
		Force.SET:
			v = force
	body.velocity = v

	# A push throws you out of dashes and wallruns, and off the floor if it lifts you.
	var in_move := state == State.DASH or state == State.DASH_AIM or state == State.WALLRUN
	if in_move or (state == State.GROUND and v.y > 0.0):
		change_state(State.AIR)
		left_floor_at = -INF            # being launched doesn't leave a coyote jump behind
		left_wall_at = -INF             # ...or a coyote wall kick
	suppress_air_control(control_lock)
	force_applied.emit(force, mode, source)


## A continuous push in m/s², for things that act over time (wind zones, pull fields).
## Call it every physics frame while it applies. On the ground the run rules win over small pushes.
func add_acceleration(acceleration: Vector3) -> void:
	_accel += acceleration


## Turns air control off, then fades it back in over duration seconds.
func suppress_air_control(duration: float) -> void:
	if duration <= 0.0 or time + duration < _control_lock_until:
		return                          # a longer suppression is already running
	_control_lock_time = duration
	_control_lock_until = time + duration


## 0..1 multiplier on air control. Squared fade-in: stays low for a moment, then comes back quickly.
func air_control_scale() -> float:
	var left := _control_lock_until - time
	if left <= 0.0:
		return 1.0
	var t := 1.0 - left / _control_lock_time
	return t * t


# ================================================================ gravity

func apply_gravity(delta: float) -> void:
	var vy := body.velocity.y
	var g := rise_gravity()
	if absf(vy) < apex_speed:
		g *= apex_gravity_mult          # hang at the top
	elif vy < 0.0:
		g *= fall_gravity_mult          # fall faster than you rise
	g *= gravity_scale()                # lighter the faster you move
	body.velocity.y = maxf(vy - g * delta, -max_fall_speed)


## 1 at run speed or below, sliding down to speed_gravity_mult at speed_gravity_full_mult x run.
func gravity_scale() -> float:
	var t := inverse_lerp(run_speed, speed_gravity_full_mult * run_speed, horizontal_speed())
	return lerpf(1.0, speed_gravity_mult, clampf(t, 0.0, 1.0))


## Gravity and jump speed come from height and time, so you tune what you feel.
func rise_gravity() -> float:
	return 2.0 * jump_height / (time_to_apex * time_to_apex)


func jump_velocity() -> float:
	return 2.0 * jump_height / time_to_apex


# ================================================================ input timing

func jump_buffered() -> bool:
	return time - jump_pressed_at <= jump_buffer


func consume_jump() -> void:
	jump_pressed_at = -INF


func in_bhop_window() -> bool:
	return state == State.GROUND and time - landed_at < ground.bhop_window


func state_name() -> String:
	return State.keys()[state]


func _read_input() -> void:
	input = Input.get_vector("left", "right", "forward", "backward")
	tilt.emit(input)
	wish = Vector3.ZERO
	if input != Vector2.ZERO and camera_controller:
		# Flat camera axes, so looking up or down never slows you.
		var b := camera_controller.global_basis
		wish = (flat(b.x) * input.x + flat(b.z) * input.y).normalized()


# ================================================================ shared helpers

func horizontal() -> Vector3:
	return Vector3(body.velocity.x, 0.0, body.velocity.z)


func set_horizontal(h: Vector3) -> void:
	body.velocity.x = h.x
	body.velocity.z = h.z


func horizontal_speed() -> float:
	return horizontal().length()


## v flattened onto the ground plane and normalized (ZERO if it was straight up or down).
func flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z).normalized()


func flat_look_direction() -> Vector3:
	return flat(-camera_controller.global_basis.z)


## Rotates a flat direction toward a target by at most max_angle radians.
func turn_toward(dir: Vector3, target: Vector3, max_angle: float) -> Vector3:
	var angle := dir.signed_angle_to(target, Vector3.UP)
	return dir.rotated(Vector3.UP, clampf(angle, -max_angle, max_angle))


## Braking = input pointing mostly against your velocity.
func is_brake_input(dir: Vector3, input_dir: Vector3) -> bool:
	return input_dir != Vector3.ZERO and rad_to_deg(dir.angle_to(input_dir)) >= brake_angle


## Fades excess speed: a percentage per second (rate) plus a fixed amount (tail_decay).
## The percentage gives the fast start; the fixed amount makes sure it actually finishes.
## Tiny leftovers snap to zero.
func decay(excess: float, rate: float, delta: float) -> float:
	var e := excess * exp(-rate * delta) - tail_decay * delta
	return e if e >= 0.05 else 0.0


# ================================================================ combat

func _on_parry_succeeded(res: AttackResult) -> void:
	if res.request.impact_beat == _last_parry_beat:
		return
	_last_parry_beat = res.request.impact_beat

	# A parry never stops or changes your speed. In the air it refills your moves.
	if state != State.GROUND:
		air_budget.refresh(&"parry")
	# Later: hitstop snap-back, drive-by bonuses.
