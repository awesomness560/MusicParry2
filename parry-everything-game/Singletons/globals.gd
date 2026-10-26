extends Node

var player : Player

var temp_enemy_marker : Marker3D

func get_player_position():
	if is_instance_valid(player):
		print("Requested player position but player not set globally")
		player = null
		return null
	return player.global_position
