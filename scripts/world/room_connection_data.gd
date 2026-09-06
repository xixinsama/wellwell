@tool
class_name RoomConnectionData
extends Resource

enum Direction {
	NONE,
	UP,
	DOWN,
	LEFT,
	RIGHT,
}

@export var from_room_id := ""
@export var from_entrance_id := ""
@export var to_room_id := ""
@export var to_spawn_id := ""
@export var direction := Direction.NONE
