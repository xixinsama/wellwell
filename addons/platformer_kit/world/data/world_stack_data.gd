@tool
class_name WorldStack
extends Resource

## An authored stack of worlds — the "multi-layer world" of the level hierarchy:
## blocks (1x1 chunk rooms) build rooms, rooms build a [WorldData], and a stack
## stacks worlds into parallel slices.
##
## Layer 0 is the bottom slice and every following entry sits one level above it.
## The editor's 3D view draws exactly these layers, in this order, and nothing
## else: a world that is not listed here is not part of the stack. The runtime
## ignores stacks — they only describe how the author sees the worlds together.

@export var stack_id := ""
@export var display_name := ""
## Bottom slice first.
@export var layers: Array[WorldData] = []


## Index of [param world_id] in the stack, or -1.
func get_layer_index(world_id: String) -> int:
	for index: int in range(layers.size()):
		var world: WorldData = layers[index]
		if world != null and world.world_id == world_id:
			return index
	return -1


func has_world(world_id: String) -> bool:
	return get_layer_index(world_id) >= 0


func get_world_ids() -> Array[String]:
	var result: Array[String] = []
	for world: WorldData in layers:
		if world != null and not world.world_id.is_empty():
			result.append(world.world_id)
	return result


func get_layer_count() -> int:
	return layers.size()


## Drops empty slots and duplicate worlds while keeping the authored order.
func normalize() -> void:
	var seen: Dictionary = {}
	var cleaned: Array[WorldData] = []
	for world: WorldData in layers:
		if world == null or world.world_id.is_empty() or seen.has(world.world_id):
			continue
		seen[world.world_id] = true
		cleaned.append(world)
	layers = cleaned


## Puts [param world] in the stack at [param index] (append when out of range).
func insert_world(world: WorldData, index: int = -1) -> bool:
	if world == null or world.world_id.is_empty() or has_world(world.world_id):
		return false
	normalize()
	if index < 0 or index > layers.size():
		layers.append(world)
	else:
		layers.insert(index, world)
	return true


func remove_world(world_id: String) -> bool:
	var index := get_layer_index(world_id)
	if index < 0:
		return false
	layers.remove_at(index)
	return true


## Moves the layer at [param from_index] to [param to_index].
func move_layer(from_index: int, to_index: int) -> bool:
	normalize()
	if from_index < 0 or from_index >= layers.size():
		return false
	var target := clampi(to_index, 0, layers.size() - 1)
	if target == from_index:
		return false
	var world: WorldData = layers[from_index]
	layers.remove_at(from_index)
	layers.insert(target, world)
	return true
