class_name RoomTransition
extends RefCounted

static func resolve(world: Resource, from_room_id: String, entrance: Node) -> Dictionary:
	if world == null or entrance == null:
		return {}
	var target_room_id := String(entrance.get("target_room_id"))
	var target_spawn_id := String(entrance.get("target_spawn_id"))
	if target_room_id.is_empty() or not world.has_room(target_room_id):
		return {}
	return {"from_room_id": from_room_id, "to_room_id": target_room_id, "to_spawn_id": target_spawn_id}

