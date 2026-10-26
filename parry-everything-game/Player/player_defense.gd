extends Node
class_name PlayerDefense
## Child of the player. Sends timestamped parry presses to the resolver and handles the lockout.

signal parry_started                     # play parry animation
signal parry_succeeded(result: AttackResult)
signal hit_taken(result: AttackResult)

@export var parry_action: StringName = &"parry"
@export var parry_recovery := 0.3        # lockout after a press; 0 = spamming allowed
@export var input_offset_ms := 0.0       # player input calibration
@export var debug_print := true

@export var normalParrySound : AudioStreamPlayer
@export var perfectParrySound : AudioStreamPlayer

var _locked_until := -INF


func _ready() -> void:
	CombatResolver.attack_resolved.connect(_on_attack_resolved)
	CombatResolver.parry_whiffed.connect(_on_parry_whiffed)


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed(parry_action, false):
		return
	if Conductor.song_time < _locked_until:
		return                           # still in recovery: press ignored
	_locked_until = Conductor.song_time + parry_recovery
	CombatResolver.register_press(Conductor.precise_time() - input_offset_ms / 1000.0)
	parry_started.emit()


func _on_attack_resolved(res: AttackResult) -> void:
	if res.is_parry():
		_locked_until = -INF             # a successful parry cancels the lockout
		parry_succeeded.emit(res)
		if res.outcome == res.Outcome.PERFECT_PARRY:
			perfectParrySound.play()
		else:
			normalParrySound.play()
	else:
		hit_taken.emit(res)
	if debug_print:
		var ms := " %+.0f ms" % (res.offset * 1000.0) if res.is_parry() else ""
		print("%s %s%s  (beat %d, %d on beat)" % [res.outcome_name(), res.request.attack_kind, ms,
			res.request.impact_beat, res.group.size()])

func _on_parry_whiffed(press_time: float) -> void:
	if debug_print:
		print("WHIFF  (pressed at %.3fs)" % press_time)

func is_locked() -> bool:
	return Conductor.song_time < _locked_until
