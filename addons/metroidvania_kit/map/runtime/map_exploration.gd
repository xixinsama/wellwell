class_name MapExploration
extends RefCounted

## Turns the fog's saved exploration ("room:x,y" ids in world cell coordinates)
## into per-room local cells the map renderers can draw.
##
## Fog cells are global world cells; the room's canonical cell origin comes from
## [MapDefinitionBuilder], so a 22-cell odd chunk row matches the fog exactly.

var version := -1

var _cells: Dictionary[String, Dictionary] = {}


func refresh(explored_cell_ids: Array[String], definition: Resource) -> void:
	_cells.clear()
	if definition == null:
		version = -1
		return
	var origins: Dictionary[String, Vector2i] = {}
	for room: Resource in definition.get("rooms"):
		if room == null:
			continue
		var room_id := String(room.get("room_id"))
		origins[room_id] = MapDefinitionBuilder.room_cell_origin(room)
	for cell_id: String in explored_cell_ids:
		var separator := cell_id.rfind(":")
		if separator <= 0:
			continue
		var room_id := cell_id.substr(0, separator)
		if not origins.has(room_id):
			continue
		var coords := cell_id.substr(separator + 1).split(",", false)
		if coords.size() != 2 or not coords[0].is_valid_int() or not coords[1].is_valid_int():
			continue
		var local := Vector2i(int(coords[0]), int(coords[1])) - origins[room_id]
		var room_cells: Dictionary = _cells.get(room_id, {})
		if room_cells.is_empty():
			_cells[room_id] = room_cells
		room_cells[local] = true


func cells_for(room_id: String) -> Dictionary:
	return _cells.get(room_id, {})


func has_any(room_id: String) -> bool:
	return not (_cells.get(room_id, {}) as Dictionary).is_empty()


func explored_count(room_id: String) -> int:
	return (_cells.get(room_id, {}) as Dictionary).size()


## Exploration ratio over the whole room area, so an empty room and a dense room
## count the same way. Rooms without any explored cell return 0.
func ratio(room_id: String, definition: Resource) -> float:
	var room: Resource = definition.call("get_room", StringName(room_id)) if definition != null else null
	if room == null:
		return 0.0
	var size := MapDefinitionBuilder.room_cell_size(room)
	var total := size.x * size.y
	if total <= 0:
		return 0.0
	return clampf(float(explored_count(room_id)) / float(total), 0.0, 1.0)
