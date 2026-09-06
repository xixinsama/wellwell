extends Node

class MethodCompatibleRoot extends Node2D:
	var room_id := "fake"
	var room_size_chunks := Vector2i.ONE

	func get_room_content() -> Node:
		return null

	func get_preview_root() -> Node:
		return null

	func get_manifest() -> Dictionary:
		return {}

class OverridingAuthoringRoot extends "res://scripts/authoring/room_authoring_root.gd":
	var external_room_content: Node
	var external_preview_root: Node

	func get_room_content() -> Node:
		return external_room_content

	func get_preview_root() -> Node:
		return external_preview_root

const RoomAuthoringRootScript: Script = preload("res://scripts/authoring/room_authoring_root.gd")
const RoomAuthoringContractScript: Script = preload("res://scripts/authoring/room_authoring_contract.gd")
const SpawnPointScript: Script = preload("res://scripts/world/spawn_point.gd")
const DerivedSpawnPointScript: Script = preload("res://tests/world/derived_spawn_point_fixture.gd")
const RoomEntranceScript: Script = preload("res://scripts/world/room_entrance.gd")
const WorldEntityScript: Script = preload("res://scripts/world/world_entity.gd")


func run() -> Array[String]:
	var failures: Array[String] = []
	var valid_root = _make_root()
	var entities: Node = valid_root.get_node("RoomContent/Entities")
	var spawn_a: Node = SpawnPointScript.new()
	spawn_a.spawn_id = "spawn_a"
	entities.add_child(spawn_a)
	var spawn_b: Node = DerivedSpawnPointScript.new()
	spawn_b.spawn_id = "spawn_b"
	entities.add_child(spawn_b)
	valid_root.preview_spawn_id = "spawn_b"
	var preview_spawn: Node = SpawnPointScript.new()
	preview_spawn.spawn_id = "preview_spawn"
	valid_root.get_node("PreviewOnly").add_child(preview_spawn)
	var entrance: Node = RoomEntranceScript.new()
	entrance.entity_id = "exit_a"
	entities.add_child(entrance)
	var persistent_entity: Node = WorldEntityScript.new()
	persistent_entity.entity_id = "switch_a"
	persistent_entity.persistent = true
	entities.add_child(persistent_entity)

	var result: Dictionary = RoomAuthoringContractScript.validate(valid_root)
	if not (result.get("errors", []) as Array).is_empty():
		failures.append("valid authoring root produced errors: %s" % result.get("errors"))
	var manifest: Dictionary = valid_root.get_manifest()
	if manifest.get("room_id") != "room_a":
		failures.append("manifest room_id mismatch")
	if manifest.get("room_size_chunks") != Vector2i(2, 1):
		failures.append("manifest room_size_chunks mismatch")
	if manifest.get("entrance_ids") != ["exit_a"]:
		failures.append("manifest entrance IDs are not deterministic")
	if manifest.get("spawn_ids") != ["spawn_a", "spawn_b"]:
		failures.append("manifest should contain only sorted RoomContent spawn IDs")
	if manifest.get("persistent_entity_ids") != ["switch_a"]:
		failures.append("manifest persistent entity IDs mismatch")
	valid_root.free()

	var mismatched_preview = _make_root()
	mismatched_preview.preview_spawn_id = "preview_a"
	var only_spawn: Node = SpawnPointScript.new()
	only_spawn.spawn_id = "start"
	mismatched_preview.get_node("RoomContent/Entities").add_child(only_spawn)
	var mismatched_preview_result: Dictionary = RoomAuthoringContractScript.validate(mismatched_preview)
	if not _contains_error(mismatched_preview_result, "preview_spawn_id does not reference a SpawnPoint: preview_a"):
		failures.append("unknown preview_spawn_id was not rejected")
	mismatched_preview.free()

	var missing_root_children = _make_root()
	missing_root_children.get_node("PreviewOnly").name = "RenamedPreview"
	var missing_root_result: Dictionary = RoomAuthoringContractScript.validate(missing_root_children)
	if not _contains_error(missing_root_result, "missing root node: PreviewOnly"):
		failures.append("missing PreviewOnly was not rejected")
	missing_root_children.free()

	var missing_room_content = _make_root()
	missing_room_content.get_node("RoomContent").name = "RenamedRoomContent"
	var missing_room_content_result: Dictionary = RoomAuthoringContractScript.validate(missing_room_content)
	if not _contains_error(missing_room_content_result, "missing root node: RoomContent"):
		failures.append("missing RoomContent was not rejected")
	missing_room_content.free()

	for child_name: String in ["Background", "Terrain", "Entities", "Foreground"]:
		var missing_content = _make_root()
		missing_content.get_node("RoomContent/" + child_name).name = "Renamed" + child_name
		var missing_content_result: Dictionary = RoomAuthoringContractScript.validate(missing_content)
		if not _contains_error(missing_content_result, "RoomContent missing node: %s" % child_name):
			failures.append("missing content node was not rejected: %s" % child_name)
		missing_content.free()

	for layer_name: String in ["BackTiles", "SolidTiles", "GlassTiles", "VisionBlockTiles", "DetailTiles", "MarkerTiles"]:
		var missing_layer = _make_root()
		missing_layer.get_node("RoomContent/Terrain/" + layer_name).name = "Renamed" + layer_name
		var missing_layer_result: Dictionary = RoomAuthoringContractScript.validate(missing_layer)
		if not _contains_error(missing_layer_result, "Terrain missing layer: %s" % layer_name):
			failures.append("missing terrain layer was not rejected: %s" % layer_name)
		missing_layer.free()

	var invalid_metadata = _make_root()
	invalid_metadata.room_id = ""
	invalid_metadata.room_size_chunks = Vector2i(0, -1)
	var invalid_metadata_result: Dictionary = RoomAuthoringContractScript.validate(invalid_metadata)
	if not _contains_error(invalid_metadata_result, "room_id must be non-empty"):
		failures.append("empty room_id was not rejected")
	if not _contains_error(invalid_metadata_result, "room_size_chunks must be positive on both axes"):
		failures.append("invalid room_size_chunks was not rejected")
	invalid_metadata.free()

	var duplicate_cases: Array[Dictionary] = [
		{"label": "spawn", "script": SpawnPointScript, "property": "spawn_id", "error": "duplicate spawn ID: duplicate"},
		{"label": "entrance", "script": RoomEntranceScript, "property": "entity_id", "error": "duplicate entrance ID: duplicate"},
		{"label": "persistent entity", "script": WorldEntityScript, "property": "entity_id", "error": "duplicate persistent entity ID: duplicate", "persistent": true},
	]
	for duplicate_case: Dictionary in duplicate_cases:
		var duplicate_root = _make_root()
		var first_duplicate: Node = duplicate_case["script"].new()
		first_duplicate.set(duplicate_case["property"], "duplicate")
		if duplicate_case.get("persistent", false):
			first_duplicate.persistent = true
		duplicate_root.get_node("RoomContent/Entities").add_child(first_duplicate)
		var second_duplicate: Node = duplicate_case["script"].new()
		second_duplicate.set(duplicate_case["property"], "duplicate")
		if duplicate_case.get("persistent", false):
			second_duplicate.persistent = true
		duplicate_root.get_node("RoomContent/Entities").add_child(second_duplicate)
		var duplicate_result: Dictionary = RoomAuthoringContractScript.validate(duplicate_root)
		if not _contains_error(duplicate_result, duplicate_case["error"]):
			failures.append("duplicate IDs were not rejected: %s" % duplicate_case["label"])
		duplicate_root.free()

	var empty_ids = _make_root()
	var empty_entrance: Node = RoomEntranceScript.new()
	empty_ids.get_node("RoomContent/Entities").add_child(empty_entrance)
	var empty_spawn: Node = SpawnPointScript.new()
	empty_spawn.spawn_id = ""
	empty_ids.get_node("RoomContent/Entities").add_child(empty_spawn)
	var empty_entity: Node = WorldEntityScript.new()
	empty_entity.persistent = true
	empty_ids.get_node("RoomContent/Entities").add_child(empty_entity)
	var empty_ids_result: Dictionary = RoomAuthoringContractScript.validate(empty_ids)
	if not _contains_error(empty_ids_result, "entrance ID must be non-empty"):
		failures.append("empty entrance ID was not rejected")
	if not _contains_error(empty_ids_result, "spawn ID must be non-empty"):
		failures.append("empty spawn ID was not rejected")
	if not _contains_error(empty_ids_result, "persistent entity ID must be non-empty"):
		failures.append("empty persistent entity ID was not rejected")
	empty_ids.free()

	var compatible_root := MethodCompatibleRoot.new()
	var compatible_result: Dictionary = RoomAuthoringContractScript.validate(compatible_root)
	if not _contains_error(compatible_result, "root must use RoomAuthoringRoot"):
		failures.append("method-compatible non-authoring root was accepted")
	compatible_root.free()

	var external_root: Node = _make_root()
	var overriding_root := OverridingAuthoringRoot.new()
	overriding_root.external_room_content = external_root.get_node("RoomContent")
	overriding_root.external_preview_root = external_root.get_node("PreviewOnly")
	var overriding_result: Dictionary = RoomAuthoringContractScript.validate(overriding_root)
	if not _contains_error(overriding_result, "missing root node: RoomContent"):
		failures.append("overridden RoomContent accessor bypassed direct-child validation")
	if not _contains_error(overriding_result, "missing root node: PreviewOnly"):
		failures.append("overridden PreviewOnly accessor bypassed direct-child validation")
	overriding_root.free()
	external_root.free()
	return failures


func _make_root():
	var root = RoomAuthoringRootScript.new()
	root.room_id = "room_a"
	root.display_name = "Room A"
	root.room_size_chunks = Vector2i(2, 1)
	root.preview_spawn_id = ""
	root.tags = PackedStringArray(["intro", "test"])
	var room_content := Node2D.new()
	room_content.name = "RoomContent"
	root.add_child(room_content)
	for child_name: String in ["Background", "Terrain", "Entities", "Foreground"]:
		var child := Node2D.new()
		child.name = child_name
		room_content.add_child(child)
		if child_name == "Terrain":
			for layer_name: String in ["BackTiles", "SolidTiles", "GlassTiles", "VisionBlockTiles", "DetailTiles", "MarkerTiles"]:
				var layer := TileMapLayer.new()
				layer.name = layer_name
				child.add_child(layer)
	var preview_only := Node2D.new()
	preview_only.name = "PreviewOnly"
	root.add_child(preview_only)
	return root


func _contains_error(result: Dictionary, expected: String) -> bool:
	for error: String in result.get("errors", []):
		if error == expected:
			return true
	return false
