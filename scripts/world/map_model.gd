class_name MapModel
extends RefCounted

static func build(world: Resource, explored_chunks: Array[String], current_room_id: String) -> Dictionary:
	var rooms: Array[Dictionary] = []
	var explored: Dictionary[String, bool] = {}
	for id: String in explored_chunks:
		explored[id] = true
	if world == null:
		return {"rooms": rooms, "connections": [], "current_room_id": current_room_id}
	for room: Resource in world.rooms:
		if room == null or room.room_id.is_empty():
			continue
		var chunks: Array[Dictionary] = []
		for chunk_id: String in room.get_chunk_ids(world.world_id):
			chunks.append({"id": chunk_id, "explored": explored.has(chunk_id)})
		rooms.append({
			"room_id": room.room_id,
			"display_name": room.display_name,
			"rect": room.get_chunk_rect(),
			"chunks": chunks,
			"current": room.room_id == current_room_id,
			"color": room.map_color,
		})
	var connections: Array[Dictionary] = []
	for connection: Resource in world.connections:
		if connection == null:
			continue
		connections.append({
			"from_room_id": connection.from_room_id,
			"to_room_id": connection.to_room_id,
			"direction": connection.direction,
		})
	return {"rooms": rooms, "connections": connections, "current_room_id": current_room_id}

