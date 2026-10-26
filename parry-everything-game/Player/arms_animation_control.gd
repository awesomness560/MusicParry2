extends Node
class_name PlayerAnimator
## Plays the player's animations and parry sounds in response to gameplay signals.
## Purely presentation: never affects timing, lockout or judgment.

@export var anim: AnimationPlayer
@export var defense: PlayerDefense
@export var normalParrySound: AudioStreamPlayer
@export var perfectParrySound: AudioStreamPlayer

@export_group("Clips")
@export var idle_clip: StringName = &"FP_Idle_Pose"
@export var parry_fail_clip: StringName = &"FP_Parry_Stance"
@export var parry_success_clip: StringName = &"FP_Parry_Success"

@export_group("Timing")
@export var blend_time := 0.05              # blend into an action
@export var return_blend_time := 0.12       # blend back to idle after holding a pose
@export var success_hold := 0.25            # seconds to hold the success pose after its clip ends
@export var success_contact_time := 0.0     # seconds into the success clip where the deflect lands

enum Action { IDLE, PARRY_FAIL, PARRY_SUCCESS }

var _action := Action.IDLE
var _clip_left := 0.0        # seconds until the current clip reaches its last frame
var _hold_left := 0.0        # seconds to hold the last frame afterwards (success only)
var _last_success_beat := -1


func _ready() -> void:
	defense.parry_started.connect(_on_parry_started)
	defense.parry_succeeded.connect(_on_parry_succeeded)
	_go_idle(0.0)


func _process(delta: float) -> void:
	if _action == Action.IDLE:
		return

	# still playing into the pose
	if _clip_left > 0.0:
		_clip_left -= delta
		return

	# clip done: holding its last frame
	match _action:
		Action.PARRY_FAIL:
			# hold the stance for exactly as long as the player is locked out
			if not defense.is_locked():
				_go_idle(return_blend_time)
		Action.PARRY_SUCCESS:
			_hold_left -= delta
			if _hold_left <= 0.0:
				_go_idle(return_blend_time)


# ---------------------------------------------------------------- reactions

func _on_parry_started() -> void:
	# every press plays immediately so input always feels responsive
	_start(Action.PARRY_FAIL, parry_fail_clip, 0.0)


func _on_parry_succeeded(res: AttackResult) -> void:
	# two attacks on the same beat send two results: only react once
	if res.request.impact_beat == _last_success_beat:
		return
	_last_success_beat = res.request.impact_beat

	var sound := perfectParrySound if res.outcome == AttackResult.Outcome.PERFECT_PARRY else normalParrySound
	if sound:
		sound.play()

	# the result arrives slightly after the beat; start further in so the deflect lines up with the impact
	var late := Conductor.song_time - res.request.impact_time
	_start(Action.PARRY_SUCCESS, parry_success_clip, success_contact_time + late)
	_hold_left = success_hold


# ---------------------------------------------------------------- helpers

func _start(action: Action, clip: StringName, from: float) -> void:
	var length := anim.get_animation(clip).length
	from = clampf(from, 0.0, length)
	_action = action
	_clip_left = length - from
	anim.play(clip, blend_time)
	anim.seek(from, true)    # also restarts the clip if it was already playing


func _go_idle(blend: float) -> void:
	_action = Action.IDLE
	_clip_left = 0.0
	anim.play(idle_clip, blend)
