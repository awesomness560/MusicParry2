extends Node
class_name PlayerTricks
## Trick input. For now: hold to twirl the knife. A parry press cancels the twirl.

signal twirl_started
signal twirl_ended(cancelled: bool)      # cancelled = interrupted by a parry

@export var defense: PlayerDefense
@export var twirl_action: StringName = &"trick"

var twirling := false


func _ready() -> void:
	defense.parry_started.connect(_on_parry_started)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(twirl_action, false):
		if defense.is_locked():
			return                       # can't start a trick during parry recovery
		twirling = true
		twirl_started.emit()
	elif event.is_action_released(twirl_action):
		if twirling:
			twirling = false
			twirl_ended.emit(false)


func _on_parry_started() -> void:
	if twirling:
		twirling = false
		twirl_ended.emit(true)
