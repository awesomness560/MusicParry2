extends Node3D
class_name CameraController
## Mouse look plus camera feel: speed FOV, FOV punches on moves, roll for strafing and wallruns,
## headbob, and a landing dip. Purely presentation: reads the movement, never changes it.

@export var playerNode: CharacterBody3D
@export var camera: Camera3D
@export var movement: PlayerMovement
@export var mouse_sensitivity: float = 0.003
@export var min_pitch: float = -89.0
@export var max_pitch: float = 89.0

@export_group("Speed FOV")
@export var min_fov := 80.0             ## FOV at run speed and below
@export var max_fov := 110.0            ## FOV at the speed cap at the highest rank
@export_range(0.0, 1.0) var low_rank_reach := 0.6  ## share of the min-max range the lowest rank can use at its cap
@export_range(1.0, 1.5) var fov_overshoot := 1.2   ## going over the cap (dash exits, launches) can widen past it, up to this much
@export_range(0.2, 1.0) var fov_curve := 0.7  ## 1 = linear. Lower = more change at lower speeds.
@export var fov_rise_speed := 10.0      ## how fast FOV widens as you speed up
@export var fov_fall_speed := 5.0       ## how fast it narrows as you slow down

@export_group("FOV Punch")
@export var dash_punch := 10.0          ## degrees added instantly on a dash, then fading
@export var wall_kick_punch := 6.0
@export var double_jump_punch := 3.0
@export var force_punch_per_run := 1.5  ## degrees per (force strength / run speed) from apply_force
@export var max_punch := 20.0
@export var aim_zoom := 10.0            ## degrees the FOV narrows while aiming a hold dash
@export var punch_recover := 6.0        ## how fast punches fade

@export_group("Roll")
@export var tiltDegree := 1.5           ## roll when strafing
@export var wallrun_tilt := 8.0         ## roll away from the wall while wallrunning
@export var roll_speed := 10.0          ## how fast roll follows its target
@export var cameraTiltNode: Node3D

@export_group("Headbob")
@export var headbobFrequency := 2.0
@export var headBobAmplitude := 0.01
@export var viewBobbingNode: Node3D

@export_group("Landing")
@export var land_kick_per_speed := 0.04 ## downward push on the view per m/s of landing speed (20 m/s ≈ 4–5 cm dip)
@export var land_kick_max := 1.6        ## caps the push (≈ 9 cm dip at most)
@export var land_stiffness := 150.0     ## how firmly the view springs back up
@export var land_damping := 18.0        ## higher = less bounce on the way back
@export var hard_landing_speed := 40.0  ## landings at least this fast also shake the camera
@export var hard_landing_shake := 0.6   ## shake strength for hard landings (0 = never shake)

@export_group("Falling")
@export var fallingDisplacementNode: Node3D
@export var fallingDisplacement := 0.05 ## how much the arms move down when falling
@export var fallingTweenTime := 0.3

var pitch := 0.0

var _input := Vector2.ZERO              # movement input, from the movement's tilt signal
var _fov := 0.0                         # smoothed speed FOV
var _punch := 0.0                       # FOV punch on top, fading out
var _headbob_time := 0.0
var _bob_weight := 0.0                  # 0..1, fades headbob in on the ground and out in the air
var _land_offset := 0.0                 # view height offset from landing (spring position)
var _land_velocity := 0.0               # spring velocity
var _falling_tween: Tween
var _is_falling := false


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_CameraShake3D._init_camera_shake(camera)
	_fov = min_fov
	camera.fov = min_fov

	movement.dashed.connect(func(_dir, _hold, _dur): punch_fov(dash_punch))
	movement.wall_kicked.connect(func(_dir): punch_fov(wall_kick_punch))
	movement.double_jumped.connect(func(): punch_fov(double_jump_punch))
	movement.force_applied.connect(_on_force_applied)
	movement.landed.connect(_on_landed)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		rotate_y(-event.relative.x * mouse_sensitivity)
		pitch -= event.relative.y * mouse_sensitivity
		pitch = clamp(pitch, deg_to_rad(min_pitch), deg_to_rad(max_pitch))
		rotation.x = pitch


func _physics_process(delta: float) -> void:
	_update_fov(delta)
	_update_roll(delta)
	_update_bob(delta)
	_update_falling()


## Connected to the movement's tilt signal.
func tilt(input_vector: Vector2) -> void:
	_input = input_vector


## Adds a quick FOV kick that fades out. Public so anything can use it (parries, explosions...).
func punch_fov(degrees: float) -> void:
	_punch = minf(_punch + degrees, max_punch)


# ================================================================ FOV

## Two parts multiplied together:
##   speed part: how far you are from run speed (0) to your current cap (1), so every rank gets a full sweep
##   rank part:  how much of the FOV range your rank may use, from low_rank_reach at D to all of it at the top rank
func speed_fov() -> float:
	var run := movement.run_speed
	var cap := movement.speed_cap()
	var top: float = movement.rank_caps.max() if not movement.rank_caps.is_empty() else cap / run

	var speed_part := clampf((movement.horizontal_speed() - run) / maxf(cap - run, 0.01), 0.0, fov_overshoot)
	var rank_t := clampf((cap / run - 1.0) / maxf(top - 1.0, 0.01), 0.0, 1.0)
	var reach := lerpf(low_rank_reach, 1.0, rank_t)
	return min_fov + (max_fov - min_fov) * pow(speed_part, fov_curve) * reach


func _update_fov(delta: float) -> void:
	var target := speed_fov()
	var aiming := movement.state == PlayerMovement.State.DASH_AIM
	if aiming:
		target -= aim_zoom
	# While aiming, time is slowed, so scale the smoothing back up to real time to keep the zoom snappy.
	var dt := delta / maxf(Engine.time_scale, 0.01) if aiming else delta
	var rate := fov_rise_speed if target > _fov else fov_fall_speed
	_fov = lerpf(_fov, target, 1.0 - exp(-rate * dt))
	_punch *= exp(-punch_recover * delta)
	camera.fov = _fov + _punch


func _on_force_applied(force: Vector3, _mode: PlayerMovement.Force, _source: StringName) -> void:
	punch_fov(force.length() / movement.run_speed * force_punch_per_run)


# ================================================================ roll

func _update_roll(delta: float) -> void:
	var target := -_input.x * tiltDegree            # strafe left = lean left
	if movement.state == PlayerMovement.State.WALLRUN:
		# Which side the wall is on, from the camera's point of view: +1 = wall on the left.
		var side := global_basis.x.dot(movement.wallrun.normal)
		target = -side * wallrun_tilt               # lean away from the wall
	var z := lerpf(cameraTiltNode.rotation_degrees.z, target, 1.0 - exp(-roll_speed * delta))
	cameraTiltNode.rotation_degrees.z = z


# ================================================================ headbob and landing

func _update_bob(delta: float) -> void:
	var on_ground := movement.state == PlayerMovement.State.GROUND
	var moving := movement.horizontal_speed() > 0.5
	_bob_weight = move_toward(_bob_weight, 1.0 if on_ground and moving else 0.0, delta * 6.0)
	if on_ground:
		_headbob_time += delta * movement.horizontal_speed()

	var bob := sin(_headbob_time * headbobFrequency) * headBobAmplitude * _bob_weight
	# Landing spring: pulled back to 0, with damping so it settles instead of wobbling.
	var spring := -land_stiffness * _land_offset - land_damping * _land_velocity
	_land_velocity += spring * delta
	_land_offset += _land_velocity * delta
	viewBobbingNode.position = Vector3(0.0, bob + _land_offset, 0.0)


## Landing pushes the spring downward instead of moving the view instantly,
## so the dip eases down over a few frames and comes back up smoothly.
func _on_landed(impact_speed: float) -> void:
	_land_velocity -= minf(impact_speed * land_kick_per_speed, land_kick_max)
	if hard_landing_shake > 0.0 and impact_speed >= hard_landing_speed:
		_CameraShake3D._custom_shake(hard_landing_shake, 0.12)


# ================================================================ arms

func _update_falling() -> void:
	var falling := playerNode.velocity.y < 0.0
	if falling == _is_falling:
		return
	_is_falling = falling
	if _falling_tween:
		_falling_tween.kill()
	_falling_tween = create_tween()
	var target_y := -fallingDisplacement if falling else 0.0
	_falling_tween.tween_property(fallingDisplacementNode, "position:y", target_y, fallingTweenTime)
