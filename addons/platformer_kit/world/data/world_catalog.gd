@tool
class_name WorldCatalog
extends Resource

## Ordered list of worlds offered by the map selection screen.
##
## Add or remove entries in the inspector. The UI builds one row per valid
## world; missing resources and empty world ids are skipped.

@export var worlds: Array[WorldData] = []


func get_worlds() -> Array[WorldData]:
	var result: Array[WorldData] = []
	var seen: Dictionary[String, bool] = {}
	for world: WorldData in worlds:
		if world == null or world.world_id.is_empty():
			continue
		if seen.has(world.world_id):
			continue
		seen[world.world_id] = true
		result.append(world)
	return result


func find_world(world_id: String) -> WorldData:
	for world: WorldData in get_worlds():
		if world.world_id == world_id:
			return world
	return null
