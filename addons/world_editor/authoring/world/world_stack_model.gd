class_name WorldStackModel
extends RefCounted

## Pure model behind the World editor's stacked-world view.
##
## Several worlds can overlay the same chunk grid and connect through SHUTTLE
## doors. The editor draws them as parallel slices and needs two things from
## here: the door links of every world (PORTAL pairs inside one slice, SHUTTLE
## pairs across slices) and the layer order of the stack. Nothing in this file
## touches the scene tree, the editor API or the file system, so it stays
## headless testable.

## End point drawn for a door whose partner does not exist.
const DANGLING_STUB := Vector2(56, -40)


## Stable, fully saturated hue per world id; the drawing layer applies alpha.
func layer_color(world_id: String) -> Color:
	var hue := float(posmod(world_id.hash(), 360)) / 360.0
	return Color.from_hsv(hue, 1.0, 0.95)


## Classifies every door link of every world. [param doors] entries are
## {world_id, layer, room_id, door_id, door_kind, target_world_id,
## target_room_id, target_door_id, position (world pixels)}.
##
## Returns {links: Array[Dictionary], dangling_count: int}. Each link is
## {kind ("portal"/"shuttle"), paired, from_world_id, from_layer, from_room_id,
## from_door_id, from_position, to_world_id, to_layer, to_room_id, to_door_id,
## to_position}. A mutual pair is emitted once.
func build_door_links(doors: Array[Dictionary]) -> Dictionary:
	var index: Dictionary = {}
	for door: Dictionary in doors:
		index[_door_key(door)] = door
	var links: Array[Dictionary] = []
	var seen: Dictionary = {}
	var dangling := 0
	var ordered := doors.duplicate()
	ordered.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return _door_key(left) < _door_key(right)
	)
	for door: Dictionary in ordered:
		var world_id := String(door.get("world_id", ""))
		var room_id := String(door.get("room_id", ""))
		var door_id := String(door.get("door_id", ""))
		if world_id.is_empty() or door_id.is_empty():
			continue
		var target_world_id := String(door.get("target_world_id", world_id))
		if target_world_id.is_empty():
			target_world_id = world_id
		var target_room_id := String(door.get("target_room_id", ""))
		var target_door_id := String(door.get("target_door_id", ""))
		var target: Dictionary = index.get(
			"%s\u001f%s\u001f%s" % [target_world_id, target_room_id, target_door_id],
			{}
		)
		var paired := (
			not target.is_empty()
			and String(target.get("target_door_id", "")) == door_id
			and _door_target_world(target) == world_id
			and String(target.get("target_room_id", "")) == room_id
		)
		var cross := target_world_id != world_id
		var from_key := "%s\u001f%s\u001f%s" % [world_id, room_id, door_id]
		var to_key := "%s\u001f%s\u001f%s" % [target_world_id, target_room_id, target_door_id]
		var pair_keys: Array[String] = [from_key, to_key]
		pair_keys.sort()
		var pair_key := pair_keys[0] + "\u001e" + pair_keys[1]
		if seen.has(pair_key):
			continue
		seen[pair_key] = true
		if not paired:
			dangling += 1
		var from_position: Vector2 = door.get("position", Vector2.ZERO)
		var to_position: Vector2 = from_position + DANGLING_STUB
		var to_layer := int(door.get("layer", 0))
		if not target.is_empty():
			to_position = target.get("position", to_position)
			to_layer = int(target.get("layer", to_layer))
		links.append({
			"kind": "shuttle" if cross else "portal",
			"paired": paired,
			"from_world_id": world_id,
			"from_layer": int(door.get("layer", 0)),
			"from_room_id": room_id,
			"from_door_id": door_id,
			"from_position": from_position,
			"to_world_id": target_world_id,
			"to_layer": to_layer,
			"to_room_id": target_room_id,
			"to_door_id": target_door_id,
			"to_position": to_position,
		})
	return {"links": links, "dangling_count": dangling}


## PORTAL links inside [param world_id] from its own door annotations.
## Positions come back in world pixels, ready for the 2D canvas.
func build_portal_links(world: WorldData, world_id: String, annotations_by_room: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if world == null or world_id.is_empty():
		return result
	var doors := collect_world_doors(world, world_id, 0, annotations_by_room)
	for link: Dictionary in build_door_links(doors).get("links", []):
		if String(link.get("kind", "")) != "portal":
			continue
		if String(link.get("from_world_id", "")) != world_id:
			continue
		result.append(link)
	return result


## Converts one world's door annotations into stack door records.
func collect_world_doors(
	world: WorldData,
	world_id: String,
	layer: int,
	annotations_by_room: Dictionary
) -> Array[Dictionary]:
	var doors: Array[Dictionary] = []
	if world == null:
		return doors
	for room_id: String in world.get_room_ids():
		var origin := Vector2(world.get_room_pixel_rect(room_id).position)
		for annotation: Dictionary in annotations_by_room.get(room_id, []):
			if annotation.get("type", &"") != RoomAnnotationService.TYPE_DOOR:
				continue
			doors.append({
				"world_id": world_id,
				"layer": layer,
				"room_id": room_id,
				"door_id": String(annotation.get("id", "")),
				"door_kind": int(annotation.get("door_kind", 0)),
				"target_world_id": String(annotation.get("target_world_id", "")),
				"target_room_id": String(annotation.get("target_room_id", "")),
				"target_door_id": String(annotation.get("target_door_id", "")),
				"position": origin + (annotation.get("position", Vector2.ZERO) as Vector2),
			})
	doors.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return _door_key(left) < _door_key(right)
	)
	return doors


# --- Layer order ---------------------------------------------------------------

## The order the editor actually shows: [param saved] filtered to worlds that
## still exist in the catalog, and when that is empty, every other catalog world
## in catalog order so the stack is never blank.
func resolve_stack_order(
	current_world_id: String,
	saved: PackedStringArray,
	catalog_ids: Array[String]
) -> Array[String]:
	var result: Array[String] = []
	var seen: Dictionary = {}
	for world_id: String in saved:
		if world_id.is_empty() or world_id == current_world_id:
			continue
		if not catalog_ids.has(world_id) or seen.has(world_id):
			continue
		seen[world_id] = true
		result.append(world_id)
	if not result.is_empty():
		return result
	for world_id: String in catalog_ids:
		if world_id.is_empty() or world_id == current_world_id or seen.has(world_id):
			continue
		seen[world_id] = true
		result.append(world_id)
	return result


func add_to_stack_order(order: Array[String], world_id: String) -> Array[String]:
	var result: Array[String] = order.duplicate()
	if world_id.is_empty() or result.has(world_id):
		return result
	result.append(world_id)
	return result


func remove_from_stack_order(order: Array[String], world_id: String) -> Array[String]:
	var result: Array[String] = []
	for value: String in order:
		if value != world_id:
			result.append(value)
	return result


## Moves one entry; out-of-range indices leave the order untouched.
func move_in_stack_order(order: Array[String], from_index: int, to_index: int) -> Array[String]:
	var result: Array[String] = order.duplicate()
	if from_index < 0 or from_index >= result.size():
		return result
	var target := clampi(to_index, 0, result.size() - 1)
	if target == from_index:
		return result
	var value: String = result[from_index]
	result.remove_at(from_index)
	result.insert(target, value)
	return result


static func _door_key(door: Dictionary) -> String:
	return "%s\u001f%s\u001f%s" % [
		String(door.get("world_id", "")),
		String(door.get("room_id", "")),
		String(door.get("door_id", "")),
	]


static func _door_target_world(door: Dictionary) -> String:
	var target := String(door.get("target_world_id", ""))
	return target if not target.is_empty() else String(door.get("world_id", ""))
