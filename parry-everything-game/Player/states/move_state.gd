extends Node
class_name MoveState
## Base for movement states. PlayerMovement calls these four functions;
## each state only writes the parts that are unique to it.

var motor: PlayerMovement    # set by PlayerMovement in _ready
var body: Player


## Called when this state becomes active. old = the state we came from.
func enter(_old: PlayerMovement.State) -> void:
	pass


## Called when this state stops being active. new = the state we're going to.
func exit(_new: PlayerMovement.State) -> void:
	pass


## Before the move: change velocity, handle input.
func physics_update(_delta: float) -> void:
	pass


## After the move: look at what the world did (landed, touched a wall...) and switch state if needed.
func after_move() -> void:
	pass
