extends Node3D
class_name HealthManager

signal died  ## Emitted when died

@export var take_no_damage_fr: bool = false
@export var max_health: float = 100

var current_health: float:
	set = set_health


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	initialize_health()


func set_health(_health: float) -> float:
	current_health = _health
	if current_health <= 0:
		died.emit()
	return current_health


func take_damage(amount: float, attack_result: AttackResult):
	#Check for death
	if attack_result.outcome == AttackResult.Outcome.HIT:
		return
	if not take_no_damage_fr:
		current_health -= amount
	DamageNumbers.spawn_number(global_position, amount, attack_result)
	pass


func initialize_health():
	current_health = max_health
