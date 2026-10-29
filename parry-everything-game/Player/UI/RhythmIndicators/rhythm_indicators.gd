extends Control
class_name AttackNotes
## Rhythm-game style attack view: every booked attack becomes a dot that travels to the
## crosshair and arrives exactly on its impact beat. A thread links each dot back to its
## attacker, or to the screen edge in its direction if the attacker is off screen.

enum State { WAITING, ACTIVE, HIT, CANCELLED }

@export var crosshair: Control                  # ColorRect with crosshair.gdshader
@export var crosshair_size := 64.0

@export_group("Approach")
@export var approach_beats := 2.0               # every dot travels for this many beats
@export var constant_distance := true           # on = start on the ring (same speed for all)
												# off = start at the enemy (or screen edge if off screen)
@export var ring_radius := 280.0                # px from the centre where dots start (constant mode)
@export var fade_in_time := 0.08                # quick fade when a dot appears

@export_group("Look")
@export var dot_radius := 9.0
@export var dot_outline := 2.5
@export var outline_color := Color(0, 0, 0, 0.6)
@export var default_color := Color(0.45, 0.85, 0.7)
@export var kind_colors := {
	&"melee": Color(0.45, 0.85, 0.7),
	&"projectile": Color(1.0, 0.7, 0.3),
	&"laser": Color(0.7, 0.6, 1.0),
}
@export var show_threads := true
@export var thread_width := 2.0
@export var thread_dash := 8.0
@export var thread_alpha := 0.55
@export var source_marker_radius := 5.0
@export var show_beat_ticks := true             # marks where the dot will be on each beat
@export var tick_radius := 3.0
@export var screen_margin := 40.0               # inset used for "on screen" and edge points

@export_group("Impact / cancel")
@export var hit_time := 0.22                    # expanding ring at the crosshair on arrival
@export var cancel_time := 0.15
@export var crosshair_flash_time := 0.18
@export var crosshair_pulse_sharpness := 4.0

class Note:
	var request: AttackRequest
	var color: Color
	var state := State.WAITING
	var age := 0.0                              # seconds since it became visible
	var t := 0.0                                # seconds in HIT / CANCELLED
	var last_world := Vector3.ZERO
	var last_pos := Vector2.ZERO

var _notes: Array[Note] = []
var _flash := 0.0
var _cross_mat: ShaderMaterial


func _ready() -> void:
	set_anchors_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_IGNORE
	CombatResolver.attack_resolved.connect(_on_attack_resolved)
	AttackScheduler.attack_booked.connect(_on_booked)
	AttackScheduler.attack_cancelled.connect(_on_cancelled)
	Conductor.time_jumped.connect(func(_t): _notes.clear())
	if crosshair:
		crosshair.show_behind_parent = true     # crosshair under the dots
		crosshair.mouse_filter = MOUSE_FILTER_IGNORE
		_cross_mat = crosshair.material as ShaderMaterial


# ---------------------------------------------------------------- scheduler events

func _on_attack_resolved(res: AttackResult) -> void:
	if res.is_parry() and is_visible_in_tree():
		_flash = 1.0

func _on_booked(r: AttackRequest) -> void:
	if not is_visible_in_tree():
		return
	var n := Note.new()
	n.request = r
	n.color = kind_colors.get(r.attack_kind, kind_colors.get(String(r.attack_kind), default_color))
	var tgt := _target(r)
	if tgt:
		n.last_world = tgt.global_position
	_notes.append(n)


func _on_cancelled(r: AttackRequest) -> void:
	for i in range(_notes.size() - 1, -1, -1):
		var n := _notes[i]
		if n.request != r:
			continue
		if n.state == State.WAITING:
			_notes.remove_at(i)                 # never shown, just drop it
		elif n.state == State.ACTIVE:
			n.state = State.CANCELLED
			n.t = 0.0


# ---------------------------------------------------------------- per frame

func _process(delta: float) -> void:
	if not is_visible_in_tree():
		_notes.clear()
		return

	var now := Conductor.song_time
	for i in range(_notes.size() - 1, -1, -1):
		var n := _notes[i]
		var tgt := _target(n.request)
		if tgt:
			n.last_world = tgt.global_position
		match n.state:
			State.WAITING:
				if now >= _appear_time(n.request):
					n.state = State.ACTIVE
			State.ACTIVE:
				n.age += delta
				if now >= n.request.impact_time:
					n.state = State.HIT
					n.t = 0.0
			State.HIT:
				n.t += delta
				if n.t >= hit_time:
					_notes.remove_at(i)
			State.CANCELLED:
				n.t += delta
				if n.t >= cancel_time:
					_notes.remove_at(i)

	_update_crosshair(delta)
	queue_redraw()


func _update_crosshair(delta: float) -> void:
	_flash = maxf(_flash - delta / crosshair_flash_time, 0.0)
	if crosshair == null:
		return
	crosshair.size = Vector2.ONE * crosshair_size
	crosshair.position = size * 0.5 - crosshair.size * 0.5
	if _cross_mat:
		var pulse := 0.0
		if Conductor.playing and not Conductor.stream_paused and Conductor.song_beat >= 0.0:
			pulse = pow(1.0 - fposmod(Conductor.song_beat, 1.0), crosshair_pulse_sharpness)
		_cross_mat.set_shader_parameter("flash", _flash)
		_cross_mat.set_shader_parameter("pulse", pulse)


# ---------------------------------------------------------------- drawing

func _draw() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var now := Conductor.song_time
	var center := size * 0.5

	for n in _notes:
		match n.state:
			State.ACTIVE:
				_draw_active(n, cam, center, now)
			State.HIT:
				var k := clampf(n.t / hit_time, 0.0, 1.0)
				var c := n.color
				c.a = 1.0 - k
				draw_arc(center, dot_radius * (1.0 + 2.5 * k), 0.0, TAU, 32, c, 3.0, true)
			State.CANCELLED:
				var k := clampf(n.t / cancel_time, 0.0, 1.0)
				var c := n.color
				c.a = 1.0 - k
				draw_circle(n.last_pos, dot_radius * (1.0 - 0.6 * k), c)


func _draw_active(n: Note, cam: Camera3D, center: Vector2, now: float) -> void:
	var r := n.request
	var appear := _appear_time(r)
	var span := maxf(r.impact_time - appear, 0.0001)
	var progress := clampf((now - appear) / span, 0.0, 1.0)
	var alpha := clampf(n.age / fade_in_time, 0.0, 1.0)

	var src := _source(cam, n.last_world, center)
	var start: Vector2 = src["start"]
	var origin: Vector2 = src["origin"]
	var pos := start.lerp(center, progress)        # linear: constant speed reads as timing
	n.last_pos = pos

	if show_threads:
		var tc := n.color
		tc.a = thread_alpha * alpha
		draw_dashed_line(origin, pos, tc, thread_width, thread_dash)
		tc.a = 0.6 * alpha
		draw_circle(origin, source_marker_radius, tc)

	# where the dot will be on each upcoming beat, so players can count in
	if show_beat_ticks:
		var first := ceili(Conductor.time_to_beat(now))
		for b in range(first, r.impact_beat):
			var tp := (Conductor.beat_to_time(b) - appear) / span
			if tp <= progress:
				continue
			var kc := n.color
			kc.a = 0.5 * alpha
			draw_circle(start.lerp(center, tp), tick_radius, kc)

	var rad := dot_radius * (1.0 + 0.3 * pow(progress, 4.0))
	var oc := outline_color
	oc.a *= alpha
	draw_circle(pos, rad + dot_outline, oc)
	var dc := n.color
	dc.a = alpha
	draw_circle(pos, rad, dc)


# ---------------------------------------------------------------- helpers

func _appear_time(r: AttackRequest) -> float:
	return r.impact_time - approach_beats * Conductor.seconds_per_beat()


func _target(r: AttackRequest) -> Node3D:
	if is_instance_valid(r.track_target):
		return r.track_target
	if is_instance_valid(r.attacker) and r.attacker is Node3D:
		return r.attacker
	return null


## start = where the dot begins its path; origin = where the thread starts.
func _source(cam: Camera3D, world: Vector3, center: Vector2) -> Dictionary:
	# camera-space direction: matches the on-screen direction, and stays correct behind the camera
	var local := cam.global_transform.affine_inverse() * world
	var dir := Vector2(local.x, -local.y)
	dir = dir.normalized() if dir.length_squared() > 1e-8 else Vector2.UP

	var screen := cam.unproject_position(world)
	var inner := Rect2(Vector2.ZERO, size).grow(-screen_margin)
	var on_screen := not cam.is_position_behind(world) and inner.has_point(screen)

	var origin := screen if on_screen else _edge_point(center, dir)
	var start: Vector2
	if constant_distance:
		start = center + dir * ring_radius
	else:
		start = origin                          # straight from the enemy, or the screen edge
	return { "start": start, "origin": origin }


func _edge_point(center: Vector2, dir: Vector2) -> Vector2:
	var half := size * 0.5 - Vector2(screen_margin, screen_margin)
	var tx := half.x / absf(dir.x) if absf(dir.x) > 1e-6 else INF
	var ty := half.y / absf(dir.y) if absf(dir.y) > 1e-6 else INF
	return center + dir * minf(tx, ty)
