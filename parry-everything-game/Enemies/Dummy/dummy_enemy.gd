extends Node3D

@export var attack_indicator: Marker3D
@export var mesh: MeshInstance3D               # what flashes on results

@export_group("Attack")
@export var auto_attack := true
@export var attack_cooldown := 0.6             # seconds after an attack lands before requesting again
@export var lead_time := 0.8                   # seconds from windup start to impact
@export var priority := 0.0
@export var max_wait_beats := 8
@export var attack_kind: StringName = &"melee"

@export_group("Test keys")
@export var attack_key: Key = KEY_U
@export var cancel_key: Key = KEY_C

@export_group("Flash")
@export var parried_color := Color(1.0, 0.1, 0.1)   # got parried: stand-in for taking damage
@export var hit_color := Color(1.0, 0.6, 0.1)       # landed a hit on the player
@export var flash_time := 0.25

var _req: AttackRequest
var _base_scale := Vector3.ONE
var _pop := 0.0
var _player_in_range := false
var _next_attack_time := -INF
var _flash_mat: StandardMaterial3D
var _flash := 0.0


func _ready() -> void:
	Globals.temp_enemy_marker = attack_indicator
	_base_scale = mesh.scale
	CombatResolver.attack_resolved.connect(_on_attack_resolved)

	# overlay material drawn on top of the mesh, faded in for flashes
	_flash_mat = StandardMaterial3D.new()
	_flash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_flash_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_flash_mat.albedo_color = Color(parried_color, 0.0)
	if mesh:
		mesh.material_overlay = _flash_mat


# ---------------------------------------------------------------- range

func _on_area_3d_body_entered(body: Node3D) -> void:
	if body is Player:
		_player_in_range = true


func _on_area_3d_body_exited(body: Node3D) -> void:
	if body is Player:
		_player_in_range = false
		# withdraw if we haven't started swinging yet; mid-windup we're committed
		if _req and (_req.state == AttackRequest.State.PENDING or _req.state == AttackRequest.State.BOOKED):
			AttackScheduler.cancel(_req, "out_of_range")


# ---------------------------------------------------------------- input

func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.keycode == attack_key:
		_request_attack()
	elif key.keycode == cancel_key and _req:
		AttackScheduler.cancel(_req, "manual")


# ---------------------------------------------------------------- attacking

func _request_attack() -> void:
	if _req and _req.is_live():
		return
	_req = AttackRequest.new()
	_req.attacker = self
	_req.track_target = attack_indicator
	_req.attack_kind = attack_kind
	_req.lead_time = lead_time
	_req.priority = priority
	_req.max_wait_beats = max_wait_beats
	_req.booked.connect(_on_booked)
	_req.started.connect(_on_started)
	_req.impact.connect(_on_impact)
	_req.cancelled.connect(_on_cancelled)
	AttackScheduler.request(_req)
	print("[%s] requested at beat %.2f" % [name, Conductor.song_beat])


func _on_booked(impact_beat: int) -> void:
	print("[%s] booked beat %d" % [name, impact_beat])


func _on_started(lateness: float) -> void:
	print("[%s] windup started  (%.1f ms late)" % [name, lateness * 1000.0])


func _on_impact(_lateness: float) -> void:
	_pop = 1.0
	_next_attack_time = Conductor.song_time + attack_cooldown


func _on_cancelled(reason: String) -> void:
	print("[%s] cancelled: %s" % [name, reason])
	_next_attack_time = Conductor.song_time + attack_cooldown


# results for every attack come through here; only react to our own
func _on_attack_resolved(res: AttackResult) -> void:
	if res.request.attacker != self:
		return
	match res.outcome:
		AttackResult.Outcome.PERFECT_PARRY, AttackResult.Outcome.PARRY:
			print("[%s] got %s'd  (%+.0f ms)" % [name, res.outcome_name(), res.offset * 1000.0])
			_start_flash(parried_color)
		AttackResult.Outcome.HIT:
			print("[%s] HIT the player" % name)
			_start_flash(hit_color)


# ---------------------------------------------------------------- per frame

func _process(delta: float) -> void:
	if auto_attack and _player_in_range and not (_req and _req.is_live()) \
			and Conductor.song_time >= _next_attack_time:
		_request_attack()

	# crouch down during the windup, spring up big on impact
	var squash := 0.0
	if _req and _req.state == AttackRequest.State.WINDING_UP:
		squash = _req.progress(Conductor.song_time)
	_pop = move_toward(_pop, 0.0, delta * 6.0)
	var s := _base_scale
	s.y *= 1.0 - 0.35 * squash + 0.5 * _pop
	s.x *= 1.0 + 0.2 * squash + 0.25 * _pop
	s.z *= 1.0 + 0.2 * squash + 0.25 * _pop
	mesh.scale = s

	# fade the flash out
	if _flash > 0.0:
		_flash = maxf(_flash - delta / flash_time, 0.0)
		_flash_mat.albedo_color.a = _flash * 0.8


func _start_flash(color: Color) -> void:
	_flash = 1.0
	_flash_mat.albedo_color = Color(color, 0.8)
