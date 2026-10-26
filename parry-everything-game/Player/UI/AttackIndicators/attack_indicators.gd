extends Control
class_name AttackIndicators

@export var indicator_scene: PackedScene

@export_group("Test")
@export var test_auto_spawn := false
@export var test_every_n_beats := 4        # 4 = once per bar, 2 = every other beat, 1 = every beat
@export var test_beat_offset := 0          # which beat in the pattern: 0 = beat 1 of the bar, 2 = beat 3...
@export var test_lead_beats := 2.0         # how many beats the fill takes before impact
@export var test_cancel_key: Key = KEY_I

@export_group("Tracked (on screen)")
@export var base_size := 96.0              # px when the target is at reference_distance
@export var reference_distance := 8.0      # metres
@export var min_scale := 0.5
@export var max_scale := 1.6
@export var screen_margin := 48.0          # px inset from the edge that already counts as "off screen"
@export var hysteresis := 24.0             # extra inset needed to switch back, stops flicker at the edge

@export_group("Ring (off screen)")
@export var ring_radius := 160.0           # px from screen centre
@export var ring_size := 56.0
@export var morph_speed := 7.0             # morph units per second (1/7 s transition)
@export var catch_up_speed := 18.0         # how fast it slides between tracked and ring positions

@export_group("Impact / cancel")
@export var flash_time := 0.18
@export var fade_time := 0.15


enum State { ACTIVE, FLASH, FADE, CANCELLED }

class Indicator:
	var node: Control
	var mat: ShaderMaterial
	var target: Node3D
	var start_time := 0.0
	var impact_time := 0.0
	var state := State.ACTIVE
	var state_t := 0.0
	var morph := 0.0
	var offscreen := false
	var initialized := false
	var catching_up := false
	var display_pos := Vector2.ZERO
	var last_world_pos := Vector3.ZERO

var _active: Array[Indicator] = []
var _next_test_beat := 0
var _test_needs_init := true


func _ready() -> void:
	set_anchors_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_IGNORE
	Conductor.time_jumped.connect(_on_time_jumped)
	AttackScheduler.attack_started.connect(_on_attack_started)
	if Globals.temp_enemy_marker == null:
		push_warning("AttackIndicators: Globals.temp_enemy_marker is not set")


func _now() -> float:
	return Conductor.song_time


# ---------------------------------------------------------------- public API

func spawn(target: Node3D, start_time: float, impact_time: float) -> Indicator:
	if indicator_scene == null:
		push_error("AttackIndicators: indicator_scene is not set")
		return null
	var ind := Indicator.new()
	ind.node = indicator_scene.instantiate() as Control
	ind.node.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(ind.node)
	# each indicator needs its own material so progress/morph don't bleed between them
	ind.mat = (ind.node.material as ShaderMaterial).duplicate()
	ind.node.material = ind.mat
	ind.target = target
	ind.start_time = start_time
	ind.impact_time = impact_time
	ind.last_world_pos = target.global_position
	_active.append(ind)
	return ind


func cancel(ind: Indicator) -> void:
	if ind and ind.state == State.ACTIVE:
		ind.state = State.CANCELLED
		ind.state_t = 0.0


func cancel_all() -> void:
	for ind in _active:
		cancel(ind)


# ---------------------------------------------------------------- test: spawn on the beat

func _test_spawn_on_beats() -> void:
	if not test_auto_spawn or not Conductor.playing or Conductor.stream_paused:
		return
	var marker: Node3D = Globals.temp_enemy_marker
	if marker == null:
		return
	var n := maxi(test_every_n_beats, 1)
	var lead := test_lead_beats * Conductor.seconds_per_beat()
	var now := _now()

	if _test_needs_init:
		# first pattern beat whose fill hasn't started yet, so we never show a half-filled one
		var b := ceili(Conductor.time_to_beat(now + lead))
		_next_test_beat = b + posmod(test_beat_offset - b, n)
		_test_needs_init = false

	# spawn every pattern beat whose fill should have started by now
	while Conductor.beat_to_time(_next_test_beat) - lead <= now:
		var impact := Conductor.beat_to_time(_next_test_beat)
		if impact > now:    # skip ones fully missed during a lag spike
			spawn(marker, impact - lead, impact)
		_next_test_beat += n


func _on_time_jumped(_new_time: float) -> void:
	cancel_all()
	_test_needs_init = true

func _on_attack_started(r: AttackRequest) -> void:
	var target := r.track_target if r.track_target else r.attacker as Node3D
	var ind := spawn(target, r.start_time, r.impact_time)
	if ind:
		r.cancelled.connect(func(_reason): cancel(ind), CONNECT_ONE_SHOT)

func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.keycode == test_cancel_key:
		for i in range(_active.size() - 1, -1, -1):
			if _active[i].state == State.ACTIVE:
				cancel(_active[i])
				break


# ---------------------------------------------------------------- per frame

func _process(delta: float) -> void:
	_test_spawn_on_beats()

	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var now := _now()
	for i in range(_active.size() - 1, -1, -1):
		var ind := _active[i]
		if is_instance_valid(ind.target):
			ind.last_world_pos = ind.target.global_position
		elif ind.state == State.ACTIVE:
			cancel(ind)   # attacker vanished without cancelling: fade out at last known spot
		_update_placement(ind, cam, delta)
		if not _update_visuals(ind, now, delta):
			ind.node.queue_free()
			_active.remove_at(i)


func _update_placement(ind: Indicator, cam: Camera3D, delta: float) -> void:
	var world := ind.last_world_pos
	var view := size
	var center := view * 0.5

	# on-screen test with hysteresis
	var behind := cam.is_position_behind(world)
	var screen := cam.unproject_position(world)
	var inset := screen_margin + (hysteresis if ind.offscreen else 0.0)
	var inner := Rect2(Vector2.ZERO, view).grow(-inset)
	var was_offscreen := ind.offscreen
	ind.offscreen = behind or not inner.has_point(screen)

	# direction in camera space: works behind the camera too (no mirrored projection)
	var local := cam.global_transform.affine_inverse() * world
	var dir := Vector2(local.x, -local.y)
	dir = dir.normalized() if dir.length_squared() > 1e-6 else Vector2.DOWN
	var ring_pos := center + dir * ring_radius

	var target_pos := ring_pos if ind.offscreen else screen
	var target_morph := 1.0 if ind.offscreen else 0.0

	if not ind.initialized:
		# appear directly in the right mode, no morph-in on spawn
		ind.initialized = true
		ind.morph = target_morph
		ind.display_pos = target_pos
	else:
		if ind.offscreen != was_offscreen:
			ind.catching_up = true
		ind.morph = move_toward(ind.morph, target_morph, morph_speed * delta)
		if ind.catching_up:
			ind.display_pos = ind.display_pos.lerp(target_pos, 1.0 - exp(-catch_up_speed * delta))
			if ind.display_pos.distance_to(target_pos) < 2.0:
				ind.catching_up = false
		else:
			ind.display_pos = target_pos

	# size: distance-scaled when tracked, fixed on the ring
	var dist := cam.global_position.distance_to(world)
	var s := clampf(reference_distance / maxf(dist, 0.01), min_scale, max_scale)
	var px := lerpf(base_size * s, ring_size, ind.morph)

	var n := ind.node
	n.size = Vector2(px, px)
	n.pivot_offset = n.size * 0.5
	n.position = ind.display_pos - n.size * 0.5
	# arrow points along dir in ring mode; "#" stays upright when tracked
	n.rotation = lerp_angle(0.0, dir.angle() + PI * 0.5, ind.morph)


# returns false when the indicator is finished and should be removed
func _update_visuals(ind: Indicator, now: float, delta: float) -> bool:
	ind.state_t += delta
	var progress := 1.0
	var flash := 0.0
	var alpha := 1.0
	var pop := 1.0

	match ind.state:
		State.ACTIVE:
			var span := maxf(ind.impact_time - ind.start_time, 0.0001)
			progress = clampf((now - ind.start_time) / span, 0.0, 1.0)
			if now >= ind.impact_time:
				ind.state = State.FLASH
				ind.state_t = 0.0
				flash = 1.0
		State.FLASH:
			flash = 1.0 - clampf(ind.state_t / flash_time, 0.0, 1.0)
			pop = 1.0 + 0.15 * flash
			if ind.state_t >= flash_time:
				ind.state = State.FADE
				ind.state_t = 0.0
		State.FADE:
			alpha = 1.0 - clampf(ind.state_t / fade_time, 0.0, 1.0)
			if ind.state_t >= fade_time:
				return false
		State.CANCELLED:
			var t := clampf(ind.state_t / fade_time, 0.0, 1.0)
			var span := maxf(ind.impact_time - ind.start_time, 0.0001)
			progress = clampf((now - ind.start_time) / span, 0.0, 1.0)
			alpha = 1.0 - t
			pop = 1.0 - 0.4 * t
			if t >= 1.0:
				return false

	ind.mat.set_shader_parameter("progress", progress)
	ind.mat.set_shader_parameter("morph", ind.morph)
	ind.mat.set_shader_parameter("flash", flash)
	ind.node.modulate.a = alpha
	ind.node.scale = Vector2(pop, pop)
	return true
