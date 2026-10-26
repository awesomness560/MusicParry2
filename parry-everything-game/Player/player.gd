extends CharacterBody3D
class_name Player

enum MOVEMENT_STATE {GROUND, AIR, SLIDE}

var currentMovementState : MOVEMENT_STATE

@export var camera : Camera3D
@export var inFrontCameraNode : Node3D

func _ready() -> void:
	Globals.player = self
