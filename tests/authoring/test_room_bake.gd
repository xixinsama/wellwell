extends Node

## Merged test suite. Every inner class below is one original test file,
## kept in its own class so fixtures and helper names stay isolated. Do not
## add logic here: split a class back into its own file when it grows.

## tests/authoring/test_room_bake_model.gd
class RoomBakeModelCase extends Node:
	const ROOM_BAKE_PATHS: Script = preload("res://addons/world_editor/authoring/room/room_bake_paths.gd")
	const ROOM_BAKE_MANIFEST: Script = preload("res://addons/world_editor/authoring/room/room_bake_manifest.gd")
	const ROOM_DATA: Script = preload("res://addons/platformer_kit/world/data/room_data.gd")
	const ROOM_AUTHORING_ROOT: Script = preload("res://addons/world_editor/authoring/room/room_authoring_root.gd")
	const ROOM_ENTRANCE: Script = preload("res://addons/platformer_kit/world/entities/room_entrance.gd")
	const SPAWN_POINT: Script = preload("res://addons/platformer_kit/world/entities/spawn_point.gd")
	const WORLD_ENTITY: Script = preload("res://addons/platformer_kit/world/entities/world_entity.gd")


	func run() -> Array[String]:
		var failures: Array[String] = []
		_assert_sanitizes_room_ids(failures)
		_assert_generates_deterministic_paths(failures)
		_assert_rejects_invalid_manifest_inputs(failures)
		_assert_normalizes_authoring_manifest(failures)
		_assert_sorts_and_deduplicates_manifest_arrays(failures)
		_assert_applies_metadata_without_overwriting_world_fields(failures)
		return failures


	func _assert_sanitizes_room_ids(failures: Array[String]) -> void:
		if ROOM_BAKE_PATHS.sanitize_room_id(" Level 0 ") != "level_0":
			failures.append("room id whitespace or case was not normalized")
		if ROOM_BAKE_PATHS.sanitize_room_id("Boss---Room 2") != "boss_room_2":
			failures.append("invalid room id runs were not collapsed")
		if ROOM_BAKE_PATHS.sanitize_room_id("___level___") != "level":
			failures.append("leading and trailing underscores were not fully trimmed")
		if ROOM_BAKE_PATHS.sanitize_room_id(" !@#$ ") != "":
			failures.append("room id with no valid characters was not emptied")


	func _assert_generates_deterministic_paths(failures: Array[String]) -> void:
		var paths: Dictionary = ROOM_BAKE_PATHS.for_room_id("Level 0")
		var expected := {
			"room_id": "level_0",
			"runtime_scene_path": "res://scenes/rooms/generated/level_0/runtime.tscn",
			"terrain_scene_path": "res://scenes/rooms/generated/level_0/terrain.tscn",
			"room_resource_path": "res://resources/rooms/generated/level_0.tres",
		}
		if paths != expected:
			failures.append("generated paths did not match the deterministic contract")
		if paths["runtime_scene_path"] == paths["terrain_scene_path"] or paths["terrain_scene_path"] == paths["room_resource_path"]:
			failures.append("generated output paths were not distinct")


	func _assert_rejects_invalid_manifest_inputs(failures: Array[String]) -> void:
		var root := Node2D.new()
		root.set_script(preload("res://addons/world_editor/authoring/room/room_authoring_root.gd"))
		root.set("room_id", "!!!")
		var invalid_id: Dictionary = ROOM_BAKE_MANIFEST.from_authoring_root(root, "res://scenes/rooms/source/room.tscn")
		if not invalid_id.is_empty():
			failures.append("sanitized-empty room id was accepted")
		var valid_root := Node2D.new()
		valid_root.set_script(preload("res://addons/world_editor/authoring/room/room_authoring_root.gd"))
		valid_root.set("room_id", "room_a")
		if not ROOM_BAKE_MANIFEST.from_authoring_root(valid_root, "").is_empty():
			failures.append("empty source path was accepted")
		root.free()
		valid_root.free()


	func _assert_normalizes_authoring_manifest(failures: Array[String]) -> void:
		var root := Node2D.new()
		root.set_script(preload("res://addons/world_editor/authoring/room/room_authoring_root.gd"))
		root.set("room_id", "Level 0")
		root.set("display_name", "Level Zero")
		root.set("room_size_chunks", Vector2i(2, 1))
		root.set("preview_spawn_id", "spawn_a")
		root.set("tags", PackedStringArray(["platformer", "intro", "intro"]))
		var manifest: Dictionary = ROOM_BAKE_MANIFEST.from_authoring_root(root, "res://scenes/rooms/source/level_0.tscn")
		if manifest.get("room_id") != "level_0":
			failures.append("manifest room id was not sanitized")
		if manifest.get("source_scene_path") != "res://scenes/rooms/source/level_0.tscn":
			failures.append("manifest source path was not recorded")
		if manifest.get("tags") != ["intro", "platformer"]:
			failures.append("manifest tags were not sorted and deduplicated")
		for key: String in ["runtime_scene_path", "terrain_scene_path", "room_resource_path"]:
			if String(manifest.get(key, "")).is_empty():
				failures.append("manifest omitted generated path: %s" % key)
		root.free()


	func _assert_sorts_and_deduplicates_manifest_arrays(failures: Array[String]) -> void:
		var root: Node2D = ROOM_AUTHORING_ROOT.new()
		root.room_id = "room_a"
		var room_content := Node2D.new()
		room_content.name = "RoomContent"
		root.add_child(room_content)
		var entities := Node2D.new()
		entities.name = "Entities"
		room_content.add_child(entities)
		for entrance_id: String in ["z_exit", "a_exit", "z_exit"]:
			var entrance: Node = ROOM_ENTRANCE.new()
			entrance.entity_id = entrance_id
			entities.add_child(entrance)
		for spawn_id: String in ["spawn_z", "spawn_a", "spawn_z"]:
			var spawn: Node = SPAWN_POINT.new()
			spawn.spawn_id = spawn_id
			entities.add_child(spawn)
		for entity_id: String in ["switch_z", "switch_a", "switch_z"]:
			var entity: Node = WORLD_ENTITY.new()
			entity.entity_id = entity_id
			entity.persistent = true
			entities.add_child(entity)
		var manifest: Dictionary = ROOM_BAKE_MANIFEST.from_authoring_root(root, "res://scenes/rooms/source/room_a.tscn")
		if manifest.get("entrance_ids") != ["a_exit", "z_exit"]:
			failures.append("entrance IDs were not sorted and deduplicated")
		if manifest.get("spawn_ids") != ["spawn_a", "spawn_z"]:
			failures.append("spawn IDs were not sorted and deduplicated")
		if manifest.get("entity_ids") != ["switch_a", "switch_z"]:
			failures.append("entity IDs were not sorted and deduplicated")
		root.free()


	func _assert_applies_metadata_without_overwriting_world_fields(failures: Array[String]) -> void:
		var root := Node2D.new()
		root.set_script(preload("res://addons/world_editor/authoring/room/room_authoring_root.gd"))
		root.set("room_id", "Room A")
		root.set("display_name", "Room A")
		root.set("room_size_chunks", Vector2i(3, 2))
		root.set("tags", PackedStringArray(["zeta", "alpha", "zeta"]))
		var manifest: Dictionary = ROOM_BAKE_MANIFEST.from_authoring_root(root, "res://scenes/rooms/source/room_a.tscn")
		var room: Resource = ROOM_DATA.new()
		room.scene_path = "res://scenes/rooms/legacy_runtime.tscn"
		room.tags = PackedStringArray(["stale"])
		if not ROOM_BAKE_MANIFEST.apply_to_room_data(manifest, room):
			failures.append("valid manifest was not applied to RoomData")
		if room.room_id != "room_a":
			failures.append("room metadata was wrong after apply")
		if room.scene_path != "res://scenes/rooms/generated/room_a/runtime.tscn":
			failures.append("apply did not update legacy scene_path to runtime path")
		if room.tags != PackedStringArray(["alpha", "zeta"]):
			failures.append("apply did not copy normalized tags")
		root.free()


## tests/authoring/test_room_cell_crop.gd
class RoomCellCropCase extends Node:
	const TEMPLATE_SCENE := preload("res://scenes/rooms/template/level_template.tscn")
	const BAKER_SCRIPT := preload("res://addons/world_editor/authoring/room/room_baker.gd")
	const ROOM_GRID := preload("res://addons/platformer_kit/world/data/room_grid.gd")


	func run() -> Array[String]:
		var failures: Array[String] = []
		var root := TEMPLATE_SCENE.instantiate()
		var layer := root.get_node_or_null("RoomContent/Terrain/SolidTiles") as TileMapLayer
		if layer == null or layer.tile_set == null:
			root.free()
			return ["level template has no usable SolidTiles layer"]
		var source_id := _first_source_id(layer)
		var atlas := _first_atlas_coords(layer, source_id)
		if source_id < 0 or atlas.x < 0:
			root.free()
			return ["level template tileset has no atlas tile to test with"]
		layer.clear()
		layer.set_cell(Vector2i(0, 0), source_id, atlas)
		layer.set_cell(Vector2i(39, 22), source_id, atlas)
		layer.set_cell(Vector2i(0, 29), source_id, atlas)
		var baker := BAKER_SCRIPT.new()
		var dropped: int = baker.call("_crop_tile_layers", layer, Vector2i.ZERO, Vector2i.ONE)
		if dropped != 1:
			failures.append("even-row room cropped %d cells instead of 1" % dropped)
		if layer.get_used_cells().has(Vector2i(0, 29)):
			failures.append("terrain outside the room's cell frame survived the crop")
		if not layer.get_used_cells().has(Vector2i(39, 22)):
			failures.append("terrain inside the 23-cell even row was cropped")

		# An odd chunk row is one cell shorter, so its last row is the 22nd.
		layer.clear()
		layer.set_cell(Vector2i(0, 21), source_id, atlas)
		layer.set_cell(Vector2i(0, 22), source_id, atlas)
		var dropped_odd: int = baker.call("_crop_tile_layers", layer, Vector2i(0, 1), Vector2i.ONE)
		if dropped_odd != 1:
			failures.append("odd-row room cropped %d cells instead of 1" % dropped_odd)
		if layer.get_used_cells().has(Vector2i(0, 22)):
			failures.append("odd-row room kept a cell past its 22nd row")
		if not layer.get_used_cells().has(Vector2i(0, 21)):
			failures.append("odd-row room cropped a cell inside its frame")

		# A 2x2 room has four blocks: rows alternate 23 / 22 by world parity.
		var blocks := ROOM_GRID.get_room_block_cell_rects(Vector2i(0, 0), Vector2i(2, 2))
		if blocks.size() != 4:
			failures.append("2x2 room returned %d block frames instead of 4" % blocks.size())
		elif blocks[1] != Rect2i(40, 0, 40, 23) or blocks[2] != Rect2i(0, 23, 40, 22):
			failures.append("2x2 block frames are not cell-aligned: %s" % str(blocks))
		root.free()
		return failures


	func _first_source_id(layer: TileMapLayer) -> int:
		var tile_set := layer.tile_set
		for index: int in tile_set.get_source_count():
			var source_id := tile_set.get_source_id(index)
			if source_id >= 0:
				return source_id
		return -1


	func _first_atlas_coords(layer: TileMapLayer, source_id: int) -> Vector2i:
		if source_id < 0:
			return Vector2i(-1, -1)
		var source := layer.tile_set.get_source(source_id) as TileSetAtlasSource
		if source == null or source.get_tiles_count() <= 0:
			return Vector2i(-1, -1)
		return source.get_tile_id(0)


## tests/authoring/test_room_cell_frame.gd
class RoomCellFrameCase extends Node:
	const FRAME_SCRIPT := preload("res://addons/world_editor/authoring/room/room_cell_frame.gd")
	const ROOT_SCRIPT := preload("res://addons/world_editor/authoring/room/room_authoring_root.gd")


	func run() -> Array[String]:
		var failures: Array[String] = []
		_assert_border_is_flush(failures)
		_assert_multi_block_frame_is_one_grid(failures)
		_assert_root_blocks_follow_the_world_origin(failures)
		return failures


	## A 2 px stroke centred on a rectangle grown by half the width spans exactly
	## 0..2 px outside the room: no gap, no extra outward offset.
	func _assert_border_is_flush(failures: Array[String]) -> void:
		var rect: Rect2 = FRAME_SCRIPT.border_rect(Rect2i(0, 0, 40, 23))
		if rect.position != Vector2(-1.0, -1.0) or rect.size != Vector2(322.0, 186.0):
			failures.append("cell frame border is not flush with the room edge: %s" % str(rect))
		var odd: Rect2 = FRAME_SCRIPT.border_rect(Rect2i(0, 23, 40, 22))
		if odd.position != Vector2(-1.0, 183.0) or odd.size != Vector2(322.0, 178.0):
			failures.append("odd-row frame border is not flush with the 22-cell block: %s" % str(odd))


	## One outer frame plus one line per seam, so adjacent blocks never draw two
	## overlapping rectangles (which would double the seam to 4 px).
	func _assert_multi_block_frame_is_one_grid(failures: Array[String]) -> void:
		if not is_equal_approx(FRAME_SCRIPT.BORDER_PIXELS, 2.0):
			failures.append("the frame line is not 2 px")
		var thickness: float = FRAME_SCRIPT.frame_seam_width()
		if not is_equal_approx(thickness, FRAME_SCRIPT.BORDER_PIXELS):
			failures.append("frame seams are not the same 2 px line: %.1f" % thickness)
		var even_blocks: Array[Rect2i] = [
			Rect2i(0, 0, 40, 23), Rect2i(40, 0, 40, 23),
			Rect2i(0, 23, 40, 22), Rect2i(40, 23, 40, 22),
		]
		var even: Dictionary = FRAME_SCRIPT.frame_geometry(even_blocks)
		var outer: Rect2 = even["outer"]
		if outer.position != Vector2(-1.0, -1.0) or outer.size != Vector2(642.0, 362.0):
			failures.append("2x2 frame is not the union of the blocks: %s" % str(outer))
		if even["seams_x"] != [320.0]:
			failures.append("2x2 frame did not put one vertical seam at 320 px: %s" % str(even["seams_x"]))
		# Even world row: the first block row is 23 cells (184 px), the second 22 (176 px).
		if even["seams_y"] != [184.0]:
			failures.append("even-row 2x2 frame has the wrong horizontal seam: %s" % str(even["seams_y"]))

		var odd_blocks: Array[Rect2i] = [
			Rect2i(0, 0, 40, 22), Rect2i(40, 0, 40, 22),
			Rect2i(0, 22, 40, 23), Rect2i(40, 22, 40, 23),
		]
		var odd: Dictionary = FRAME_SCRIPT.frame_geometry(odd_blocks)
		if odd["seams_y"] != [176.0]:
			failures.append("odd-row 2x2 frame has the wrong horizontal seam: %s" % str(odd["seams_y"]))
		if odd["seams_x"] != [320.0]:
			failures.append("odd-row 2x2 frame changed the vertical seam: %s" % str(odd["seams_x"]))

		var single_blocks: Array[Rect2i] = [Rect2i(0, 0, 40, 23)]
		var single: Dictionary = FRAME_SCRIPT.frame_geometry(single_blocks)
		if not (single["seams_x"] as Array).is_empty() or not (single["seams_y"] as Array).is_empty():
			failures.append("a one-block room must not draw seams")


	func _assert_root_blocks_follow_the_world_origin(failures: Array[String]) -> void:
		var root: Node2D = ROOT_SCRIPT.new() as Node2D
		root.set("room_size_chunks", Vector2i.ONE)
		root.set("world_origin_chunk", Vector2i(0, 0))
		root.set("world_origin_known", true)
		if root.call("get_room_block_cell_rects") != [Rect2i(0, 0, 40, 23)]:
			failures.append("even-origin room frame is not 23 cells")
		root.set("world_origin_chunk", Vector2i(0, 1))
		if root.call("get_room_block_cell_rects") != [Rect2i(0, 0, 40, 22)]:
			failures.append("odd-origin room frame is not 22 cells")
		root.set("room_size_chunks", Vector2i(2, 2))
		if root.call("get_room_block_cell_rects") != [
			Rect2i(0, 0, 40, 22), Rect2i(40, 0, 40, 22),
			Rect2i(0, 22, 40, 23), Rect2i(40, 22, 40, 23),
		]:
			failures.append("odd-origin 2x2 frames are not 22/23 alternating")
		root.free()


## tests/authoring/test_room_terrain_slice.gd
class RoomTerrainSliceCase extends Node:
	const BAKER_SCRIPT := preload("res://addons/world_editor/authoring/room/room_baker.gd")
	const TERRAIN_PATH := "user://test_world_terrain.tscn"


	func run() -> Array[String]:
		var failures: Array[String] = []
		var tile_set := load("res://resources/tilesets/primordial_tileset.tres") as TileSet
		if tile_set == null:
			return ["primordial tileset could not be loaded"]
		var world_root := Node2D.new()
		world_root.name = "WorldTerrain"
		var terrain_root := Node2D.new()
		terrain_root.name = "Terrain"
		world_root.add_child(terrain_root)
		terrain_root.owner = world_root
		var solid := TileMapLayer.new()
		solid.name = "SolidTiles"
		solid.tile_set = tile_set
		terrain_root.add_child(solid)
		solid.owner = world_root
		solid.set_cell(Vector2i(80, 23), 0, Vector2i(1, 0))
		solid.set_cell(Vector2i(81, 23), 0, Vector2i(2, 0))
		solid.set_cell(Vector2i(10, 10), 0, Vector2i(1, 0))
		var packed := PackedScene.new()
		if packed.pack(world_root) != OK or ResourceSaver.save(packed, TERRAIN_PATH) != OK:
			world_root.free()
			return ["could not save the world terrain fixture"]
		world_root.free()

		var room_content := Node2D.new()
		room_content.name = "RoomContent"
		var source_terrain := Node2D.new()
		source_terrain.name = "Terrain"
		room_content.add_child(source_terrain)
		var source_layer := TileMapLayer.new()
		source_layer.name = "SolidTiles"
		source_layer.tile_set = tile_set
		source_terrain.add_child(source_layer)
		var baker := BAKER_SCRIPT.new()
		var result: Dictionary = baker.call(
			"_pack_sliced_terrain", room_content, Vector2i(2, 1), Vector2i.ONE, TERRAIN_PATH
		)
		if not bool(result.get("ok", false)):
			failures.append("slicing failed: %s" % str(result.get("errors", [])))
		else:
			var scene := result["scene"] as PackedScene
			var instance := scene.instantiate()
			var layer := instance.get_node_or_null("Terrain/SolidTiles") as TileMapLayer
			if layer == null:
				failures.append("slice did not keep the SolidTiles layer")
			else:
				if layer.get_cell_source_id(Vector2i(0, 0)) == -1:
					failures.append("slice did not shift the room's first world cell to local (0,0)")
				if layer.get_cell_source_id(Vector2i(1, 0)) == -1:
					failures.append("slice dropped a cell inside the room rectangle")
				if layer.get_used_cells().has(Vector2i(-70, -13)):
					failures.append("slice kept a cell outside the room rectangle")
			instance.free()
		room_content.free()
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TERRAIN_PATH))
		return failures


## tests/authoring/test_room_scene_writer.gd
class RoomSceneWriterCase extends Node:
	## Coverage for the inherited room-scene writer used by the New Room wizard.

	const WRITER := preload("res://addons/world_editor/authoring/world/room_scene_writer.gd")
	const TEMPLATE := "res://scenes/rooms/template/level_template.tscn"
	const PATH := "user://writer_room.tscn"
	const SECOND_PATH := "user://writer_room_2.tscn"
	const BAD_PATH := "user://writer_room_bad.tscn"


	func run() -> Array[String]:
		var failures: Array[String] = []
		_cleanup()
		var result: Dictionary = WRITER.write_inherited_scene(PATH, TEMPLATE, "writer_room", "Writer Room")
		if not bool(result.get("ok", false)):
			failures.append("writer failed: %s" % [result.get("errors", [])])
		else:
			_assert_written_scene(failures)
		var second: Dictionary = WRITER.write_inherited_scene(SECOND_PATH, TEMPLATE, "writer_room_2")
		if not bool(second.get("ok", false)):
			failures.append("writer failed without a display name: %s" % [second.get("errors", [])])
		else:
			var packed := load(SECOND_PATH) as PackedScene
			var root := null if packed == null else packed.instantiate()
			if root == null:
				failures.append("default-name scene could not load")
			else:
				if String(root.get("display_name")) != "writer_room_2":
					failures.append("display name did not default to the room id")
				root.free()
		if bool(WRITER.write_inherited_scene(BAD_PATH, TEMPLATE, "bad id").get("ok", true)):
			failures.append("writer accepted an invalid room id")
		if bool(WRITER.write_inherited_scene(PATH, TEMPLATE, "writer_room").get("ok", true)):
			failures.append("writer overwrote an existing room source")
		if bool(WRITER.write_inherited_scene("user://writer_room_3.tscn", "res://missing_template.tscn", "writer_3").get("ok", true)):
			failures.append("writer accepted a missing template")
		_cleanup()
		return failures


	func _assert_written_scene(failures: Array[String]) -> void:
		var packed := load(PATH) as PackedScene
		if packed == null:
			failures.append("written room scene could not load")
			return
		var root := packed.instantiate()
		if root == null:
			failures.append("written room scene could not instantiate")
			return
		if String(root.get("room_id")) != "writer_room":
			failures.append("written room scene has the wrong room_id")
		if String(root.get("display_name")) != "Writer Room":
			failures.append("written room scene has the wrong display_name")
		if root.get_node_or_null("RoomContent/Entities/StartSpawn") == null:
			failures.append("written room scene did not inherit the template entities")
		if root.get_node_or_null("PreviewOnly/Player") == null:
			failures.append("written room scene did not inherit the template preview children")
		root.free()


	func _cleanup() -> void:
		for path in [PATH, SECOND_PATH, BAD_PATH, "user://writer_room_3.tscn"]:
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


## tests/authoring/test_room_status.gd
class RoomStatusCase extends Node:
	## Coverage for the World editor room status service: fresh, stale, missing
	## artifacts/source, session bake failures, unknown fingerprints and the source
	## hash cache.

	const STATUS := preload("res://addons/world_editor/authoring/world/room_status_service.gd")
	const ROOM_DATA := preload("res://addons/platformer_kit/world/data/room_data.gd")

	const SOURCE := "user://world_status_source.tscn"
	const RUNTIME := "user://world_status_runtime.tscn"
	const TERRAIN := "user://world_status_terrain.tscn"
	const ROOM_ID := "room_status_test"


	func run() -> Array[String]:
		var failures: Array[String] = []
		_write_fixtures()
		_assert_fresh(failures)
		_assert_stale(failures)
		_assert_unknown_without_fingerprint(failures)
		_assert_unknown_without_source(failures)
		_assert_error_missing_source(failures)
		_assert_error_missing_artifact(failures)
		_assert_error_bake_failure(failures)
		_assert_hash_cache(failures)
		_cleanup()
		return failures


	func _assert_fresh(failures: Array[String]) -> void:
		var service := STATUS.new() as RoomStatusService
		var status := service.evaluate(_make_room())
		if status["state"] != RoomStatusService.FRESH:
			failures.append("fresh room was not reported fresh: %s" % status.get("state", ""))
		if String(status.get("message_key", "")) != "WE_STATUS_MSG_FRESH":
			failures.append("fresh status did not carry a localization key")


	func _assert_stale(failures: Array[String]) -> void:
		var service := STATUS.new() as RoomStatusService
		var status := service.evaluate(_make_room("deadbeef"))
		if status["state"] != RoomStatusService.STALE:
			failures.append("changed source was not reported stale: %s" % status.get("state", ""))
		if String(status.get("message_key", "")) != "WE_STATUS_MSG_STALE":
			failures.append("stale status did not carry a localization key")


	func _assert_unknown_without_fingerprint(failures: Array[String]) -> void:
		var service := STATUS.new() as RoomStatusService
		var room := _make_room()
		room.source_fingerprint = ""
		if service.evaluate(room)["state"] != RoomStatusService.UNKNOWN:
			failures.append("room without a fingerprint was not unknown")


	func _assert_unknown_without_source(failures: Array[String]) -> void:
		var service := STATUS.new() as RoomStatusService
		var room := _make_room()
		room.source_scene_path = ""
		if service.evaluate(room)["state"] != RoomStatusService.UNKNOWN:
			failures.append("room without a source path was not unknown")


	func _assert_error_missing_source(failures: Array[String]) -> void:
		var service := STATUS.new() as RoomStatusService
		var room := _make_room()
		room.source_scene_path = "user://world_status_missing_source.tscn"
		if service.evaluate(room)["state"] != RoomStatusService.ERROR:
			failures.append("missing source scene was not reported as an error")


	func _assert_error_missing_artifact(failures: Array[String]) -> void:
		var service := STATUS.new() as RoomStatusService
		var room := _make_room()
		DirAccess.remove_absolute(ProjectSettings.globalize_path(RUNTIME))
		var status := service.evaluate(room)
		if status["state"] != RoomStatusService.ERROR:
			failures.append("missing runtime scene was not reported as an error")
		_write(RUNTIME, "[gd_scene format=3]\n")
		service.clear_cache()
		if service.evaluate(room)["state"] != RoomStatusService.FRESH:
			failures.append("restored runtime scene did not return to fresh")


	func _assert_error_bake_failure(failures: Array[String]) -> void:
		var service := STATUS.new() as RoomStatusService
		var room := _make_room()
		service.mark_bake_failure(ROOM_ID, "bake exploded")
		var status := service.evaluate(room)
		if status["state"] != RoomStatusService.ERROR or not String(status["message"]).contains("bake exploded"):
			failures.append("session bake failure was not reported with its message")
		service.clear_bake_failure(ROOM_ID)
		if service.evaluate(room)["state"] != RoomStatusService.FRESH:
			failures.append("cleared bake failure did not return to fresh")


	func _assert_hash_cache(failures: Array[String]) -> void:
		var service := STATUS.new() as RoomStatusService
		var calls := [0]
		service.hash_provider = func(path: String) -> String:
			calls[0] += 1
			return FileAccess.get_sha256(path)
		var room := _make_room()
		service.evaluate(room)
		service.evaluate(room)
		if int(calls[0]) != 1:
			failures.append("source hash was recomputed for an unchanged file (%d calls)" % int(calls[0]))
		# A content change with a different size invalidates the cache and the state.
		_write(SOURCE, "[gd_scene format=3]\n\n[node name=\"Changed\" type=\"Node2D\"]\n")
		service.evaluate(room)
		if int(calls[0]) != 2:
			failures.append("source hash was not recomputed after the file changed (%d calls)" % int(calls[0]))
		if service.evaluate(room)["state"] != RoomStatusService.STALE:
			failures.append("rewritten source did not become stale")
		service.evaluate(room)
		if int(calls[0]) != 2:
			failures.append("hash cache did not hit after re-reading the changed file")


	func _make_room(fingerprint := "") -> RoomData:
		var room := ROOM_DATA.new() as RoomData
		room.room_id = ROOM_ID
		room.source_scene_path = SOURCE
		room.source_fingerprint = fingerprint if not fingerprint.is_empty() else FileAccess.get_sha256(SOURCE)
		room.scene_path = RUNTIME
		room.terrain_scene_path = TERRAIN
		return room


	func _write_fixtures() -> void:
		_write(SOURCE, "[gd_scene format=3]\n\n[node name=\"Source\" type=\"Node2D\"]\n")
		_write(RUNTIME, "[gd_scene format=3]\n\n[node name=\"Runtime\" type=\"Node2D\"]\n")
		_write(TERRAIN, "[gd_scene format=3]\n\n[node name=\"Terrain\" type=\"Node2D\"]\n")


	func _write(path: String, content: String) -> void:
		var file := FileAccess.open(path, FileAccess.WRITE)
		if file == null:
			return
		file.store_string(content)
		file.close()


	func _cleanup() -> void:
		for path in [SOURCE, RUNTIME, TERRAIN]:
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


## tests/authoring/room/test_room_bake_paths.gd
class RoomBakePathsCase extends Node:
	const ROOM_BAKE_PATHS: Script = preload("res://addons/world_editor/authoring/room/room_bake_paths.gd")


	func run() -> Array[String]:
		var failures: Array[String] = []
		var paths: Dictionary = ROOM_BAKE_PATHS.for_room_id("level_2")
		if paths.get("runtime_scene_path") != "res://scenes/rooms/generated/level_2/runtime.tscn":
			failures.append("runtime output must be grouped beneath its room id")
		if paths.get("terrain_scene_path") != "res://scenes/rooms/generated/level_2/terrain.tscn":
			failures.append("terrain output must be grouped beneath its room id")
		if paths.get("room_resource_path") != "res://resources/rooms/generated/level_2.tres":
			failures.append("RoomData output must use one canonical resource path")
		return failures


## tests/authoring/room/test_source_fingerprint.gd
class SourceFingerprintCase extends Node:
	const ROOM_BAKER_PATH := "res://addons/world_editor/authoring/room/room_baker.gd"
	const FIXTURE_PATH := "user://room_baker_fingerprint_fixture.tscn"


	func run() -> Array[String]:
		var failures: Array[String] = []
		var file := FileAccess.open(FIXTURE_PATH, FileAccess.WRITE)
		if file == null:
			return ["could not create RoomBaker fingerprint fixture"]
		file.store_string("[gd_scene format=3]\n")
		file.close()
		var baker_script := load(ROOM_BAKER_PATH) as Script
		if baker_script == null or not baker_script.can_instantiate():
			return ["RoomBaker could not be loaded"]
		var baker: RefCounted = baker_script.new() as RefCounted
		if not baker.has_method("get_source_fingerprint"):
			failures.append("RoomBaker must expose get_source_fingerprint")
		else:
			var expected := FileAccess.get_sha256(FIXTURE_PATH)
			var actual: String = baker.call("get_source_fingerprint", FIXTURE_PATH)
			if actual != expected or actual.is_empty():
				failures.append("RoomBaker source fingerprint must match the saved scene bytes")
		DirAccess.remove_absolute(ProjectSettings.globalize_path(FIXTURE_PATH))
		return failures


func run() -> Array[String]:
	var failures: Array[String] = []
	failures.append_array(_run_case(RoomBakeModelCase.new()))
	failures.append_array(_run_case(RoomCellCropCase.new()))
	failures.append_array(_run_case(RoomCellFrameCase.new()))
	failures.append_array(_run_case(RoomTerrainSliceCase.new()))
	failures.append_array(_run_case(RoomSceneWriterCase.new()))
	failures.append_array(_run_case(RoomStatusCase.new()))
	failures.append_array(_run_case(RoomBakePathsCase.new()))
	failures.append_array(_run_case(SourceFingerprintCase.new()))
	return failures


func _run_case(test: Node) -> Array[String]:
	add_child(test)
	var result: Array = test.call("run")
	test.queue_free()
	var failures: Array[String] = []
	failures.assign(result)
	return failures
