extends MoveState
class_name DashState
## Handles two states: DASH (the zip itself) and DASH_AIM (holding the button in slow motion).
##   Tap:  release quickly for a short, very fast dash in your input direction.
##   Hold: past hold_threshold, time slows and you aim with the camera. Release (or reach max_hold)
##         for a long dash where you look. Longer, but you leave it with less speed than a tap.
## Free on the ground (cooldown only); in the air it costs a dash charge, spent when you press.

enum Kind { TAP, HOLD }

@export_group("Tap")
@export var tap_distance := 5.0         ## metres covered by the zip
@export var tap_duration := 0.07        ## seconds the zip lasts
@export var tap_exit_mult := 3.6        ## exit speed in x run speed (you keep your current speed if higher)
@export var tap_exit_bonus_mult := 0.4  ## extra speed on exit, in x run speed

@export_group("Hold")
@export var hold_threshold := 0.15      ## real seconds held before a press becomes a hold
@export var max_hold := 0.8             ## real seconds of aiming before the dash fires on its own
@export var hold_time_scale := 0.25     ## how slow time runs while aiming
@export var hold_distance := 14.0
@export var hold_duration := 0.2
@export var hold_exit_mult := 2.2
@export var hold_exit_bonus_mult := 0.2
@export var aim_drag := 3.0             ## how fast your speed bleeds off while aiming
@export var aim_gravity_mult := 0.25    ## gravity while aiming, so you hang in the air

@export_group("Shared")
@export var travel_over_exit := 1.5     ## the zip is always at least this many times faster than the exit
@export_range(0.0, 1.0) var up_keep := 0.35  ## share of upward speed kept when an upward dash ends
@export var cooldown := 0.4             ## seconds between dashes

var _pending := false                   # button is down and the dash hasn't fired yet
var _pressed_real := 0.0                # real time of the press (aiming runs in slow motion)
var _dir := Vector3.ZERO
var _speed := 0.0                       # zip speed
var _exit_speed := 0.0                  # exit speed including the bonus
var _ends_at := 0.0
var _ready_at := -INF
var _was_ready := true


## Called by the motor every frame, before the state update.
func handle_input() -> void:
	if Input.is_action_just_pressed("dash"):
		_press()
	if _pending:
		_check_release()
	_update_ready()


## Tells the UI when the dash becomes usable or unusable (cooldown, charges, mid-dash).
func _update_ready() -> void:
	var s := motor.state
	var busy := _pending or s == PlayerMovement.State.DASH or s == PlayerMovement.State.DASH_AIM
	var has_charge := s == PlayerMovement.State.GROUND or motor.air_budget.has(&"dash")
	var ready := not busy and motor.time >= _ready_at and has_charge
	if ready != _was_ready:
		_was_ready = ready
		motor.dash_ready_changed.emit(ready)


func _check_release() -> void:
	var held := _real_now() - _pressed_real
	var aiming := motor.state == PlayerMovement.State.DASH_AIM
	if not Input.is_action_pressed("dash"):
		_launch(Kind.HOLD if aiming else Kind.TAP)
	elif aiming and held >= max_hold:
		_launch(Kind.HOLD)                 # held too long: it fires for you
	elif not aiming and held >= hold_threshold:
		motor.change_state(PlayerMovement.State.DASH_AIM)


## 0..1 through the max hold time while aiming, for UI. 0 when not aiming.
func hold_progress() -> float:
	if motor.state != PlayerMovement.State.DASH_AIM:
		return 0.0
	return clampf((_real_now() - _pressed_real - hold_threshold) / (max_hold - hold_threshold), 0.0, 1.0)


func enter(_old: PlayerMovement.State) -> void:
	if motor.state == PlayerMovement.State.DASH_AIM:
		TimeControl.request(&"dash_aim", hold_time_scale)
		motor.dash_aim_started.emit(max_hold - (_real_now() - _pressed_real))


func exit(_new: PlayerMovement.State) -> void:
	if motor.state == PlayerMovement.State.DASH_AIM:   # still the old state here
		TimeControl.release(&"dash_aim")
		_pending = false                # covers being knocked out of the aim by a force
		motor.dash_aim_ended.emit()


func physics_update(delta: float) -> void:
	if motor.state == PlayerMovement.State.DASH_AIM:
		_aim(delta)
	else:
		body.velocity = _dir * _speed   # the zip: straight line, fixed speed, no gravity


func after_move() -> void:
	if motor.state == PlayerMovement.State.DASH_AIM:
		return                          # aiming only ends by releasing or max_hold
	if motor.time >= _ends_at:
		_finish()
	elif _dir.y < 0.0 and body.is_on_floor():
		_finish()                       # dashed down into the floor: land early


## Starts a pending dash if allowed. In the air the charge is spent now, so aiming needs one.
func _press() -> void:
	if _pending or motor.time < _ready_at:
		return
	if motor.state == PlayerMovement.State.DASH or motor.state == PlayerMovement.State.DASH_AIM:
		return
	if motor.state != PlayerMovement.State.GROUND and not motor.air_budget.spend(&"dash"):
		return
	_pending = true
	_pressed_real = _real_now()


func _launch(kind: Kind) -> void:
	_pending = false
	var tap := kind == Kind.TAP
	var b := motor.camera_controller.global_basis

	# Tap goes where your input points (forward = where you look); hold goes exactly where you aim.
	var dir := _input_direction() if tap else -b.z
	if body.is_on_floor() and dir.y < 0.0:
		dir = motor.flat(dir)           # don't dash into the floor
		if dir == Vector3.ZERO:
			dir = motor.flat_look_direction()

	var distance := tap_distance if tap else hold_distance
	var duration := tap_duration if tap else hold_duration
	var exit_mult := tap_exit_mult if tap else hold_exit_mult
	var bonus_mult := tap_exit_bonus_mult if tap else hold_exit_bonus_mult

	# Exit = the higher of your current speed or the dash's exit speed, plus the bonus. Current speed
	# only counts for the flat part, so dashing straight up can't turn horizontal speed into a rocket.
	var carried := motor.horizontal_speed() * (1.0 - absf(dir.y))
	var base_exit := maxf(carried, exit_mult * motor.run_speed)
	_exit_speed = base_exit + bonus_mult * motor.run_speed
	_speed = maxf(distance / duration, base_exit * travel_over_exit)
	_dir = dir
	_ends_at = motor.time + duration
	_ready_at = motor.time + cooldown

	motor.change_state(PlayerMovement.State.DASH)
	motor.dashed.emit(dir, not tap, duration)
	motor.dash_cooldown_started.emit(cooldown)


## While aiming: you drift and slowly lose speed, with light gravity. Time is slowed on top of this.
func _aim(delta: float) -> void:
	motor.set_horizontal(motor.horizontal() * exp(-aim_drag * delta))
	if body.is_on_floor():
		body.velocity.y = maxf(body.velocity.y, 0.0)
	else:
		body.velocity.y -= motor.rise_gravity() * aim_gravity_mult * delta


## Drops from zip speed to the exit burst, in the direction you ended up moving.
## If a wall ate part of the zip, the exit shrinks by the same share.
func _finish() -> void:
	var v := body.velocity
	var exit := Vector3.ZERO
	if v.length() > 0.1:
		var kept := clampf(v.length() / _speed, 0.0, 1.0)   # 1 = nothing blocked you
		exit = v.normalized() * _exit_speed * kept
	if exit.y > 0.0:
		exit.y *= up_keep               # an upward dash shouldn't fire you into the sky
	body.velocity = exit
	motor.change_state(PlayerMovement.State.GROUND if body.is_on_floor() else PlayerMovement.State.AIR)


## Input direction using the full camera, so forward follows where you look, up or down.
## No input = straight where you look.
func _input_direction() -> Vector3:
	var b := motor.camera_controller.global_basis
	if motor.input == Vector2.ZERO:
		return -b.z
	return (b.x * motor.input.x + b.z * motor.input.y).normalized()


func _real_now() -> float:
	return Time.get_ticks_usec() / 1_000_000.0
