extends Node

## Save-scoped register of numbered collectibles.
##
## Every [NumberPickup] registers its number and marks it collected; the set of
## numbers that exist in the running world is discovered by scanning the world's
## baked rooms, so an author only fills the number on the pickup itself. The
## screen ([code]scenes/ui/collection_screen.tscn[/code]) reads this node.
##
## State lives in the active save snapshot as module `collectibles`:
## [code]{"version": 1, "worlds": {"<world_id>": {"collected": [3, 7]}}}[/code].
## Each world keeps its own numbering, so the same number may exist in two worlds.

signal changed()

const MODULE_ID := &"collectibles"
const STATE_VERSION := 1
const SAVE_MANAGER := "/root/SaveManager"

## World whose numbers the screen currently shows. Set by [method scan_world].
var current_world_id := ""

var _collected: Dictionary = {}
var _known: Dictionary = {}
var _scanned_worlds: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var manager := get_node_or_null(SAVE_MANAGER)
	if manager == null:
		return
	if manager.has_signal("slot_selected") and not manager.is_connected("slot_selected", _on_slot_selected):
		manager.connect("slot_selected", _on_slot_selected)
	if manager.has_signal("snapshot_committing") and not manager.is_connected("snapshot_committing", _on_snapshot_committing):
		manager.connect("snapshot_committing", _on_snapshot_committing)


## Discovers every number in [param world]'s baked rooms and makes it the shown
## world. Scanned worlds are cached, so switching back is free.
func scan_world(world: WorldData) -> void:
	current_world_id = "" if world == null else world.world_id
	if current_world_id.is_empty():
		changed.emit()
		return
	if not _known.has(current_world_id):
		_known[current_world_id] = {}
	if _scanned_worlds.has(current_world_id):
		changed.emit()
		return
	_scanned_worlds[current_world_id] = true
	for room_id: String in world.get_room_ids():
		var room: Resource = world.get_room(room_id)
		if room == null:
			continue
		var scene_path := String(room.get("scene_path"))
		if scene_path.is_empty() or not ResourceLoader.exists(scene_path, "PackedScene"):
			continue
		var packed := ResourceLoader.load(scene_path, "PackedScene") as PackedScene
		if packed == null:
			continue
		var instance := packed.instantiate()
		_scan_node(instance, current_world_id)
		instance.free()
	changed.emit()


func register_number(number: int, world_id: String = "") -> void:
	var id := _resolve_world(world_id)
	if id.is_empty() or number <= 0:
		return
	var bucket: Dictionary = _known.get(id, {})
	if bucket.has(number):
		return
	bucket[number] = true
	_known[id] = bucket
	changed.emit()


func collect_number(number: int, world_id: String = "") -> bool:
	var id := _resolve_world(world_id)
	if id.is_empty() or number <= 0:
		return false
	var bucket: Dictionary = _collected.get(id, {})
	if bucket.has(number):
		return false
	bucket[number] = true
	_collected[id] = bucket
	register_number(number, id)
	changed.emit()
	return true


func is_collected(number: int, world_id: String = "") -> bool:
	var id := _resolve_world(world_id)
	if id.is_empty():
		return false
	var bucket: Dictionary = _collected.get(id, {})
	return bucket.has(number)


## Numbers the world contains, sorted. Collected numbers are always included even
## if the scan missed their room.
func get_known_numbers(world_id: String = "") -> Array[int]:
	var id := _resolve_world(world_id)
	var numbers: Array[int] = []
	if id.is_empty():
		return numbers
	for number: Variant in (_known.get(id, {}) as Dictionary):
		numbers.append(int(number))
	for number: Variant in (_collected.get(id, {}) as Dictionary):
		if not numbers.has(int(number)):
			numbers.append(int(number))
	numbers.sort()
	return numbers


func get_collected_count(world_id: String = "") -> int:
	var id := _resolve_world(world_id)
	if id.is_empty():
		return 0
	return (_collected.get(id, {}) as Dictionary).size()


func get_total(world_id: String = "") -> int:
	return get_known_numbers(world_id).size()


## Drops every session state. Used by tests and when a new game starts.
func reset() -> void:
	_collected.clear()
	_known.clear()
	_scanned_worlds.clear()
	current_world_id = ""
	changed.emit()


func write_to_snapshot(snapshot: RefCounted) -> void:
	if snapshot != null and snapshot.has_method("set_module_state"):
		snapshot.call("set_module_state", MODULE_ID, _serialize_state())


func load_from_snapshot(snapshot: RefCounted) -> void:
	_collected.clear()
	_known.clear()
	_scanned_worlds.clear()
	if snapshot != null and snapshot.has_method("get_module_state"):
		_apply_state(snapshot.call("get_module_state", MODULE_ID))
	changed.emit()


func _on_slot_selected(_slot: int, snapshot: RefCounted) -> void:
	load_from_snapshot(snapshot)


func _on_snapshot_committing(snapshot: RefCounted) -> void:
	write_to_snapshot(snapshot)


func _scan_node(node: Node, world_id: String) -> void:
	if node is NumberPickup:
		var pickup := node as NumberPickup
		var bucket: Dictionary = _known.get(world_id, {})
		bucket[pickup.number] = true
		_known[world_id] = bucket
	for child: Node in node.get_children():
		_scan_node(child, world_id)


func _resolve_world(world_id: String) -> String:
	if not world_id.is_empty():
		return world_id
	return current_world_id


func _serialize_state() -> Dictionary:
	var worlds: Dictionary = {}
	for world_id: Variant in _collected:
		var numbers: Array[int] = []
		for number: Variant in (_collected[world_id] as Dictionary):
			numbers.append(int(number))
		numbers.sort()
		worlds[String(world_id)] = {"collected": numbers}
	return {"version": STATE_VERSION, "worlds": worlds}


func _apply_state(state: Variant) -> void:
	if not state is Dictionary:
		return
	var worlds: Variant = (state as Dictionary).get("worlds", {})
	if not worlds is Dictionary:
		return
	for world_id: Variant in worlds:
		var entry: Variant = worlds[world_id]
		if not entry is Dictionary:
			continue
		var numbers: Variant = (entry as Dictionary).get("collected", [])
		if not numbers is Array:
			continue
		var bucket: Dictionary = {}
		for number: Variant in numbers:
			if number is int or number is float:
				bucket[int(number)] = true
		_collected[String(world_id)] = bucket
