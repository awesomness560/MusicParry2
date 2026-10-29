extends Node
class_name AirBudget
## How many air moves you have left this airtime.
## Landing refills it, and so does fighting (parries now; walls, kills and knife hits later).

signal spent(action: StringName, left: int)
signal refreshed(reason: StringName)

@export var double_jumps := 1
@export var dashes := 1
@export var launches := 1

var _left := {}


func _ready() -> void:
	_fill()


## True if at least one charge of this action is left.
func has(action: StringName) -> bool:
	return _left.get(action, 0) > 0


## Uses one charge. Returns false (and spends nothing) if none are left.
func spend(action: StringName) -> bool:
	if not has(action):
		return false
	_left[action] -= 1
	spent.emit(action, _left[action])
	return true


## Refills every charge. reason says why (&"landed", &"parry"...), for style and effects.
func refresh(reason: StringName) -> void:
	_fill()
	refreshed.emit(reason)


func left(action: StringName) -> int:
	return _left.get(action, 0)


func _fill() -> void:
	_left = {
		&"double_jump": double_jumps,
		&"dash": dashes,
		&"launch": launches,
	}
