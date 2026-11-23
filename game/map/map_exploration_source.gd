class_name MapExplorationSource
extends RefCounted

## Union of the saved exploration (persistence bridge, every visited room) and
## the live fog of the loaded room. The bridge alone covers normal play; the fog
## alone covers previews and the test world runner, which have no save.

var bridge: Object
var fog: Object


func get_explored_cells() -> Array[String]:
	var seen: Dictionary[String, bool] = {}
	var result: Array[String] = []
	for source: Object in [bridge, fog]:
		if source == null or not is_instance_valid(source):
			continue
		var ids: Array = []
		if source.has_method("get_explored_cells"):
			ids = source.call("get_explored_cells")
		elif source.has_method("get_explored_cell_ids"):
			ids = source.call("get_explored_cell_ids")
		for value: Variant in ids:
			var cell_id := String(value)
			if cell_id.is_empty() or seen.has(cell_id):
				continue
			seen[cell_id] = true
			result.append(cell_id)
	return result


func get_fog_version() -> int:
	var version := 0
	if bridge != null and is_instance_valid(bridge) and bridge.has_method("get_fog_version"):
		version += int(bridge.call("get_fog_version")) * 100003
	if fog != null and is_instance_valid(fog) and fog.has_method("get_exploration_version"):
		version += int(fog.call("get_exploration_version"))
	return version
