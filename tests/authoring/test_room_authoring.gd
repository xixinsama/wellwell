extends Node

## Merged test suite. Every inner class below is one original test file,
## kept in its own class so fixtures and helper names stay isolated. Do not
## add logic here: split a class back into its own file when it grows.

## tests/authoring/test_room_preview_spawn_auto.gd
class RoomPreviewSpawnAutoCase extends Node:
	## Contract for the authoring room's preview spawn: an authored ID is used while
	## it exists, a renamed preview spawn follows its SpawnPoint, and a stale ID falls
	## back to the room's first spawn instead of failing the bake.

	const ROOM_AUTHORING_ROOT: Script = preload("res://addons/world_editor/authoring/room/room_authoring_root.gd")
	const ROOM_AUTHORING_CONTRACT: Script = preload("res://addons/world_editor/authoring/room/room_authoring_contract.gd")
	const ROOM_PREVIEW_CONTROLLER: Script = preload("res://addons/world_editor/authoring/room/room_preview_controller.gd")
	const SPAWN_POINT: Script = preload("res://addons/platformer_kit/world/entities/spawn_point.gd")


	class PreviewCamera extends Node:
		var bound_target: Node2D

		func bind_target(target: Node2D) -> void:
			bound_target = target


	class PreviewHud extends Node:
		var bound_player: Node2D

		func bind_player(player: Node2D) -> void:
			bound_player = player


	func run() -> Array[String]:
		var failures: Array[String] = []
		_assert_no_spawns_resolves_empty(failures)
		_assert_first_spawn_is_the_fallback(failures)
		_assert_rename_follows_the_preview_spawn(failures)
		_assert_rename_ignores_other_spawns(failures)
		_assert_stale_preview_is_repaired_on_rename(failures)
		_assert_preview_controller_uses_the_fallback(failures)
		return failures


	func _assert_no_spawns_resolves_empty(failures: Array[String]) -> void:
		var root := _make_root("start")
		if not root.resolve_preview_spawn_id().is_empty():
			failures.append("a room without spawns resolved a preview spawn")
		if not String(root.get_manifest().get("preview_spawn_id", "x")).is_empty():
			failures.append("manifest kept a preview spawn without any SpawnPoint")
		root.free()


	func _assert_first_spawn_is_the_fallback(failures: Array[String]) -> void:
		var root := _make_root("preview_a")
		_add_spawn(root, "zeta")
		_add_spawn(root, "start")
		if root.resolve_preview_spawn_id() != "start":
			failures.append("stale preview_spawn_id did not fall back to the first sorted spawn")
		if root.get_manifest().get("preview_spawn_id") != "start":
			failures.append("manifest did not use the resolved preview spawn")
		var result: Dictionary = ROOM_AUTHORING_CONTRACT.validate(root)
		if not (result.get("errors", []) as Array).is_empty():
			failures.append("stale preview_spawn_id still fails validation: %s" % result.get("errors"))
		if (result.get("warnings", []) as Array).is_empty():
			failures.append("stale preview_spawn_id did not produce a warning")
		root.free()


	func _assert_rename_follows_the_preview_spawn(failures: Array[String]) -> void:
		var root := _make_root("start")
		_add_spawn(root, "start")
		_add_spawn(root, "entry")
		var spawn := _find_spawn(root, "start")
		if spawn == null:
			failures.append("test spawn could not be found")
			root.free()
			return
		spawn.spawn_id = "start01"
		if root.preview_spawn_id != "start01":
			failures.append("preview_spawn_id did not follow its renamed SpawnPoint")
		if root.resolve_preview_spawn_id() != "start01":
			failures.append("resolved preview spawn did not follow the rename")
		root.free()


	func _assert_rename_ignores_other_spawns(failures: Array[String]) -> void:
		var root := _make_root("start")
		_add_spawn(root, "start")
		var other := _add_spawn(root, "entry")
		other.spawn_id = "entry01"
		if root.preview_spawn_id != "start":
			failures.append("renaming an unrelated SpawnPoint changed preview_spawn_id")
		root.free()


	func _assert_stale_preview_is_repaired_on_rename(failures: Array[String]) -> void:
		var root := _make_root("gone")
		var spawn := _add_spawn(root, "entry")
		spawn.spawn_id = "entry01"
		if root.preview_spawn_id != "entry01":
			failures.append("a stale preview_spawn_id did not adopt the renamed spawn")
		root.free()


	func _assert_preview_controller_uses_the_fallback(failures: Array[String]) -> void:
		var root := _make_root("preview_a")
		var spawn := _add_spawn(root, "start")
		spawn.position = Vector2(48.0, 72.0)
		var player := root.get_node("PreviewOnly/Player") as Node2D
		var controller: Node = ROOM_PREVIEW_CONTROLLER.new() as Node
		controller.name = "RoomPreviewController"
		root.add_child(controller)
		if not bool(controller.call("setup_preview", root)):
			failures.append("preview setup failed with a stale preview_spawn_id")
		elif player.position != spawn.position:
			failures.append("preview did not place the player at the fallback spawn")
		var snapshot: RefCounted = controller.call("get_preview_snapshot")
		if snapshot == null:
			failures.append("preview did not create a snapshot for the fallback spawn")
		elif String(snapshot.get("respawn_spawn_id")) != "start":
			failures.append("preview snapshot kept the stale spawn ID")
		root.free()


	func _make_root(preview_id: String) -> RoomAuthoringRoot:
		var root: RoomAuthoringRoot = ROOM_AUTHORING_ROOT.new() as RoomAuthoringRoot
		root.room_id = "preview_room"
		root.room_size_chunks = Vector2i.ONE
		root.preview_spawn_id = preview_id
		var content := Node2D.new()
		content.name = "RoomContent"
		root.add_child(content)
		for child_name: String in ["Background", "Terrain", "Entities", "Foreground"]:
			var child := Node2D.new()
			child.name = child_name
			content.add_child(child)
			if child_name == "Terrain":
				for layer_name: String in ["BackTiles", "SolidTiles", "DetailTiles"]:
					var layer := TileMapLayer.new()
					layer.name = layer_name
					child.add_child(layer)
		var preview := Node2D.new()
		preview.name = "PreviewOnly"
		root.add_child(preview)
		var player := Node2D.new()
		player.name = "Player"
		preview.add_child(player)
		var camera := PreviewCamera.new()
		camera.name = "PixelCamera2D"
		preview.add_child(camera)
		var hud := PreviewHud.new()
		hud.name = "DebugHud"
		preview.add_child(hud)
		var fog := Node.new()
		fog.name = "FogOfWar"
		preview.add_child(fog)
		return root


	func _add_spawn(root: Node, spawn_id: String) -> SpawnPoint:
		var spawn: SpawnPoint = SPAWN_POINT.new() as SpawnPoint
		spawn.spawn_id = spawn_id
		root.get_node("RoomContent/Entities").add_child(spawn)
		return spawn


	func _find_spawn(root: Node, spawn_id: String) -> SpawnPoint:
		for child: Node in root.get_node("RoomContent/Entities").get_children():
			if child is SpawnPoint and (child as SpawnPoint).spawn_id == spawn_id:
				return child as SpawnPoint
		return null


## tests/authoring/test_level_template_contract.gd
class LevelTemplateContractCase extends Node:
	const ROOM_AUTHORING_CONTRACT: Script = preload("res://addons/world_editor/authoring/room/room_authoring_contract.gd")
	const ROOM_BAKER: Script = preload("res://addons/world_editor/authoring/room/room_baker.gd")

	const TEMPLATE_PATH := "res://scenes/rooms/template/level_template.tscn"
	const LEVEL_ZERO_PATH := "res://scenes/levels/the_world/room_00_00.tscn"
	const LAYER_NAMES: Array[String] = [
		"BackTiles",
		"SolidTiles",
		"DetailTiles",
	]


	func run() -> Array[String]:
		var failures: Array[String] = []
		var template_scene := load(TEMPLATE_PATH) as PackedScene
		var level_scene := load(LEVEL_ZERO_PATH) as PackedScene
		if template_scene == null or level_scene == null:
			failures.append("template or room_00_00 scene could not be loaded")
			return failures

		var template_root := template_scene.instantiate()
		var level_root := level_scene.instantiate()
		_assert_contract(template_root, "template", failures)
		_assert_contract(level_root, "room_00_00", failures)
		_assert_template_is_empty(template_root, failures)
		_assert_level_metadata_and_content(level_root, failures)
		_assert_preview_and_stage(level_root, failures)
		template_root.free()
		if level_root.is_inside_tree():
			remove_child(level_root)
		level_root.free()
		return failures


	func _assert_contract(root: Node, label: String, failures: Array[String]) -> void:
		var result: Dictionary = ROOM_AUTHORING_CONTRACT.validate(root)
		for error: String in result.get("errors", []):
			failures.append("%s authoring contract: %s" % [label, error])
		for layer_name: String in LAYER_NAMES:
			var layer := root.get_node_or_null("RoomContent/Terrain/%s" % layer_name)
			if not layer is TileMapLayer:
				failures.append("%s missing TileMapLayer: %s" % [label, layer_name])
			elif (layer as TileMapLayer).tile_set == null:
				failures.append("%s layer has no TileSet: %s" % [label, layer_name])


	func _assert_template_is_empty(root: Node, failures: Array[String]) -> void:
		if root.name != "RoomAuthoringRoot":
			failures.append("template root name must be RoomAuthoringRoot")
		for layer_name: String in LAYER_NAMES:
			var layer := root.get_node("RoomContent/Terrain/%s" % layer_name) as TileMapLayer
			if not layer.get_used_cells().is_empty():
				failures.append("template layer must be empty: %s" % layer_name)


	func _assert_level_metadata_and_content(root: Node, failures: Array[String]) -> void:
		if String(root.get("room_id")) != "room_00_00":
			failures.append("room_00_00 room_id override is missing")
		if String(root.get("display_name")).is_empty():
			failures.append("room_00_00 display_name override is missing")
		if root.get("room_size_chunks") != Vector2i.ONE:
			failures.append("room_00_00 validation room must remain one chunk")
		if String(root.get("preview_spawn_id")).is_empty():
			failures.append("room_00_00 preview_spawn_id must not be empty")
		var start_spawn := root.get_node_or_null("RoomContent/Entities/StartSpawn")
		if not start_spawn is SpawnPoint:
			failures.append("room_00_00 StartSpawn must be a SpawnPoint")
		elif String(start_spawn.get("spawn_id")) != String(root.get("preview_spawn_id")):
			failures.append("room_00_00 StartSpawn id must match preview_spawn_id")
		var solid := root.get_node("RoomContent/Terrain/SolidTiles") as TileMapLayer
		if solid.get_used_cells().is_empty():
			failures.append("room_00_00 validation room has no solid tiles")


	func _assert_preview_and_stage(root: Node, failures: Array[String]) -> void:
		add_child(root)
		var controller := root.get_node_or_null("RoomPreviewController")
		if controller == null:
			failures.append("room_00_00 preview controller is missing")
		else:
			var snapshot: RefCounted = controller.call("get_preview_snapshot")
			if snapshot == null:
				failures.append("room_00_00 preview controller did not initialize on scene ready")
			elif String(snapshot.get("current_room_id")) != "room_00_00":
				failures.append("room_00_00 preview snapshot has the wrong room id")
			elif int(snapshot.get("slot")) != 0:
				failures.append("room_00_00 preview snapshot must use in-memory slot 0")
		var baker: RefCounted = ROOM_BAKER.new()
		var staged: Dictionary = baker.stage(root, LEVEL_ZERO_PATH)
		if not staged.get("ok", false):
			failures.append("room_00_00 could not stage: %s" % staged.get("errors", []))
			return
		var runtime_root: Node = (staged["runtime_scene"] as PackedScene).instantiate()
		var terrain_root: Node = (staged["terrain_scene"] as PackedScene).instantiate()
		if runtime_root.get_node_or_null("PreviewOnly") != null:
			failures.append("staged runtime content included PreviewOnly")
		for layer_name: String in LAYER_NAMES:
			if terrain_root.get_node_or_null("Terrain/%s" % layer_name) == null:
				failures.append("staged terrain omitted %s" % layer_name)
		runtime_root.free()
		terrain_root.free()


## tests/authoring/test_world_room_draw.gd
class WorldRoomDrawCase extends Node:
	const CANVAS_PATH := "res://addons/world_editor/world_layout_canvas.gd"
	const WORLD_DATA := preload("res://addons/platformer_kit/world/data/world_data.gd")


	class FakeMain extends Control:
		var world_data: Resource


	func run() -> Array[String]:
		var failures: Array[String] = []
		var canvas := (load(CANVAS_PATH) as Script).new() as Control
		canvas.size = Vector2(1000.0, 700.0)
		var fake_main := FakeMain.new()
		fake_main.world_data = WORLD_DATA.new()
		add_child(canvas)
		canvas.call("set_main_screen", fake_main)
		canvas.call("reset_view")
		var requests: Array[Rect2i] = []
		canvas.connect("room_draw_requested", func(rect: Rect2i) -> void: requests.append(rect))

		canvas.call("set_room_draw_mode", true)
		if not bool(canvas.call("is_room_draw_mode")):
			failures.append("canvas did not enter room draw mode")
		_press(canvas, Vector2(500, 350))
		_move(canvas, Vector2(820, 530))
		_release(canvas, Vector2(820, 530))
		if requests != [Rect2i(0, 0, 2, 2)]:
			failures.append("room draw emitted %s instead of Rect2i(0,0,2,2)" % str(requests))

		canvas.call("set_room_draw_mode", false)
		_press(canvas, Vector2(500, 350))
		_release(canvas, Vector2(500, 350))
		if requests.size() != 1:
			failures.append("room draw emitted while the mode was off")
		canvas.free()
		fake_main.free()
		return failures


	func _press(canvas: Control, position: Vector2) -> void:
		var event := InputEventMouseButton.new()
		event.position = position
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = true
		canvas.call("_gui_input", event)


	func _move(canvas: Control, position: Vector2) -> void:
		var event := InputEventMouseMotion.new()
		event.position = position
		canvas.call("_gui_input", event)


	func _release(canvas: Control, position: Vector2) -> void:
		var event := InputEventMouseButton.new()
		event.position = position
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = false
		canvas.call("_gui_input", event)


## tests/authoring/test_components_gallery.gd
class ComponentsGalleryCase extends Node:
	## The components gallery is a copy source, so every station it advertises must
	## keep its components, its one-way flag and the phantom wall's erased terrain.
	## The room is also registered in the test world, which this guards as well.

	const GALLERY_PATH := "res://scenes/levels/test_world/components_gallery.tscn"
	const WORLD_PATH := "res://resources/worlds/test_world.tres"
	const ROOM_CONTRACT := preload("res://addons/world_editor/authoring/room/room_authoring_contract.gd")
	const ROOM_ID := "components_gallery"
	const ROOM_ORIGIN := Vector2i(3, 1)
	const PHANTOM_CELL := Vector2i(60, 18)


	func run() -> Array[String]:
		var failures: Array[String] = []
		var packed := load(GALLERY_PATH) as PackedScene
		if packed == null:
			return ["components gallery scene is missing: %s" % GALLERY_PATH]
		var room: Node = packed.instantiate()
		var validation: Dictionary = ROOM_CONTRACT.validate(room)
		for error: String in validation.get("errors", []):
			failures.append("components gallery room contract: %s" % error)
		if room.get("room_size_chunks") != Vector2i(2, 1):
			failures.append("components gallery is not a two-chunk room")
		var entities := room.get_node_or_null("RoomContent/Entities")
		if entities == null:
			room.free()
			return failures + ["components gallery has no RoomContent/Entities"]
		_assert_elevator(entities, failures)
		_assert_conveyor(entities, failures)
		_assert_waypoint(entities, failures)
		_assert_falling(entities, failures)
		_assert_one_way(entities, failures)
		_assert_door(entities, failures)
		_assert_phantom_wall(room, entities, failures)
		_assert_signs(entities, failures)
		_assert_world_registration(failures)
		room.free()
		return failures


	func _assert_elevator(entities: Node, failures: Array[String]) -> void:
		var platform := entities.get_node_or_null("01_Elevator") as AnimatableBody2D
		if platform == null:
			failures.append("01_Elevator is missing its AnimatableBody2D")
			return
		var motion := platform.get_node_or_null("ElevatorMotion")
		if motion == null or not motion.has_method("activate"):
			failures.append("01_Elevator has no ElevatorMotionComponent2D")
		if platform.get_node_or_null("RiderTrigger") == null:
			failures.append("01_Elevator has no RiderTrigger")
		if platform.get_node_or_null("CollisionShape2D") == null:
			failures.append("01_Elevator has no collision shape")


	func _assert_conveyor(entities: Node, failures: Array[String]) -> void:
		var platform := entities.get_node_or_null("02_Conveyor") as AnimatableBody2D
		if platform == null:
			failures.append("02_Conveyor is missing its AnimatableBody2D")
			return
		var surface := platform.get_node_or_null("ConveyorSurface")
		if surface == null or Vector2(surface.get("surface_velocity")) == Vector2.ZERO:
			failures.append("02_Conveyor has no moving ConveyorSurface")


	func _assert_waypoint(entities: Node, failures: Array[String]) -> void:
		var platform := entities.get_node_or_null("03_Waypoint") as AnimatableBody2D
		if platform == null:
			failures.append("03_Waypoint is missing its AnimatableBody2D")
			return
		var motion := platform.get_node_or_null("WaypointMotion")
		if motion == null or not motion.has_method("is_route_valid"):
			failures.append("03_Waypoint has no WaypointMotionComponent2D")
		elif not bool(motion.call("is_route_valid")):
			failures.append("03_Waypoint route is invalid (waypoints must start at zero)")
		var occluder := platform.get_node_or_null("FogOccluder")
		if occluder == null or not occluder.has_method("is_occluding"):
			failures.append("03_Waypoint has no FogOccluderComponent2D")
		elif occluder.call("get_world_rect") != Rect2(platform.position, Vector2(24.0, 8.0)):
			failures.append("03_Waypoint occluder does not follow its collision shape")


	func _assert_falling(entities: Node, failures: Array[String]) -> void:
		var platform := entities.get_node_or_null("04_Falling") as AnimatableBody2D
		if platform == null:
			failures.append("04_Falling is missing its AnimatableBody2D")
			return
		var motion := platform.get_node_or_null("FallMotion")
		if motion == null or not motion.has_method("activate"):
			failures.append("04_Falling has no FallMotionComponent2D")
		if platform.get_node_or_null("RiderTrigger") == null:
			failures.append("04_Falling has no RiderTrigger")


	func _assert_one_way(entities: Node, failures: Array[String]) -> void:
		var platform := entities.get_node_or_null("07_OneWayPlatform") as StaticBody2D
		if platform == null:
			failures.append("07_OneWayPlatform is missing its StaticBody2D")
			return
		var shape := platform.get_node_or_null("CollisionShape2D") as CollisionShape2D
		if shape == null or not shape.one_way_collision:
			failures.append("07_OneWayPlatform does not set CollisionShape2D.one_way_collision")


	func _assert_door(entities: Node, failures: Array[String]) -> void:
		var door := entities.get_node_or_null("05_Door") as Node2D
		if door == null:
			failures.append("05_Door is missing")
			return
		var component := door.get_node_or_null("Door")
		if component == null or not component.has_method("is_closed"):
			failures.append("05_Door has no DoorComponent2D")
		var occluder := door.get_node_or_null("FogOccluder")
		if occluder == null or not bool(occluder.call("is_occluding")):
			failures.append("05_Door does not start as a sight blocker")
		if door.get_node_or_null("Sense") == null:
			failures.append("05_Door has no sense area")


	func _assert_phantom_wall(room: Node, entities: Node, failures: Array[String]) -> void:
		var wall := entities.get_node_or_null("06_PhantomWall") as TileMapLayer
		if wall == null:
			failures.append("06_PhantomWall is missing its TileMapLayer")
			return
		if wall.collision_enabled:
			failures.append("06_PhantomWall must have collision disabled")
		if wall.get_used_cells().size() != 2:
			failures.append("06_PhantomWall does not cover its two cells")
		if not wall.has_method("reveal"):
			failures.append("06_PhantomWall has no PhantomWallComponent2D")
		var solid := room.get_node_or_null("RoomContent/Terrain/SolidTiles") as TileMapLayer
		if solid == null:
			failures.append("components gallery has no SolidTiles layer")
			return
		for cell: Vector2i in [PHANTOM_CELL, PHANTOM_CELL + Vector2i.DOWN]:
			if solid.get_cell_source_id(cell) != -1:
				failures.append("the solid wall still covers the phantom cell %s" % cell)


	func _assert_signs(entities: Node, failures: Array[String]) -> void:
		var signs := entities.get_node_or_null("Signs")
		if signs == null:
			failures.append("components gallery has no Signs node")
			return
		if signs.get_child_count() < 8:
			failures.append("components gallery signs do not label every station")


	func _assert_world_registration(failures: Array[String]) -> void:
		var world := load(WORLD_PATH) as WorldData
		if world == null:
			failures.append("could not load the test world")
			return
		if not world.has_room(ROOM_ID):
			failures.append("components gallery is not registered in the test world")
			return
		if world.get_room_origin_chunk(ROOM_ID) != ROOM_ORIGIN:
			failures.append(
				"components gallery sits at chunk %s, expected %s"
				% [world.get_room_origin_chunk(ROOM_ID), ROOM_ORIGIN]
			)
		var room_data := world.get_room(ROOM_ID)
		if room_data == null or not FileAccess.file_exists(String(room_data.scene_path)):
			failures.append("components gallery baked runtime scene is missing")


## tests/authoring/test_world_editor_main_screen.gd
class WorldEditorMainScreenCase extends Node:
	const PLUGIN := preload("res://addons/world_editor/world_editor_plugin.gd")
	const MAIN_SCENE_PATH := "res://addons/world_editor/world_editor_main.tscn"


	func run() -> Array[String]:
		var failures: Array[String] = []
		var method_names: Array[StringName] = []
		var plugin_script: Script = PLUGIN
		for method: Dictionary in plugin_script.get_script_method_list():
			method_names.append(method.get("name", &""))
		for required_method: StringName in [
			&"_has_main_screen",
			&"_make_visible",
			&"_get_plugin_name",
			&"_get_plugin_icon",
		]:
			if not method_names.has(required_method):
				failures.append("World Editor plugin is missing main-screen method: %s" % required_method)
		var packed := load(MAIN_SCENE_PATH) as PackedScene
		if packed == null:
			failures.append("World Editor main-screen scene is missing")
		else:
			var state := packed.get_state()
			if state.get_node_type(0) != &"VBoxContainer":
				failures.append("World Editor main-screen scene root is not Control")
			elif (int(_scene_node_property(state, 0, &"size_flags_vertical", 0)) & Control.SIZE_EXPAND) == 0:
				failures.append("World Editor main screen does not expand vertically")
			var layout_canvas_index := _scene_node_index(state, "Workspace/CanvasSplit/LayoutCanvas")
			if layout_canvas_index < 0 or not bool(_scene_node_property(state, layout_canvas_index, &"clip_contents", false)):
				failures.append("World Editor canvas does not clip enlarged room previews to its bounds")
			for node_path: String in [
				"WorldBar/WorldPicker",
				"CommandBar/NewRoom",
				"CommandBar/BakeRoom",
				"Workspace/RoomListPanel/RoomSearch",
				"Workspace/RoomListPanel/RoomList",
				"Workspace/CanvasSplit/InspectorPanel",
			]:
				if _scene_node_index(state, node_path) < 0:
					failures.append("World Editor workbench is missing node: %s" % node_path)
		return failures


	func _scene_node_index(state: SceneState, path: String) -> int:
		for index: int in state.get_node_count():
			if String(state.get_node_path(index)).trim_prefix("./") == path:
				return index
		return -1


	func _scene_node_property(state: SceneState, node_index: int, property: StringName, default: Variant) -> Variant:
		for property_index: int in state.get_node_property_count(node_index):
			if state.get_node_property_name(node_index, property_index) == property:
				return state.get_node_property_value(node_index, property_index)
		return default


## tests/authoring/test_world_editor_localization.gd
class WorldEditorLocalizationCase extends Node:
	## Coverage for the World editor localization helper: zh_CN/en tables, argument
	## formatting, zh* normalization and unknown-key fallback.

	const LOCALIZATION := preload("res://addons/world_editor/world_editor_localization.gd")
	const ZH := "zh_CN"


	func run() -> Array[String]:
		var failures: Array[String] = []
		LOCALIZATION.locale_override = "zh_CN"
		_assert_equals(LOCALIZATION.t("WE_NEW_WORLD"), String(LOCALIZATION.STRINGS[ZH]["WE_NEW_WORLD"]), failures, "zh button")
		_assert_equals(LOCALIZATION.t("WE_ROOMS_COUNT", [2]), String(LOCALIZATION.STRINGS[ZH]["WE_ROOMS_COUNT"]) % [2], failures, "zh count")
		_assert_equals(LOCALIZATION.t("WE_STATUS_MSG_STALE"), String(LOCALIZATION.STRINGS[ZH]["WE_STATUS_MSG_STALE"]), failures, "zh status")
		LOCALIZATION.locale_override = "en"
		_assert_equals(LOCALIZATION.t("WE_NEW_WORLD"), "New World", failures, "en button")
		_assert_equals(LOCALIZATION.t("WE_ROOMS_COUNT", [2]), "2 rooms", failures, "en count")
		LOCALIZATION.locale_override = "zh"
		_assert_equals(LOCALIZATION.t("WE_NEW_WORLD"), String(LOCALIZATION.STRINGS[ZH]["WE_NEW_WORLD"]), failures, "zh normalization")
		LOCALIZATION.locale_override = "fr"
		_assert_equals(LOCALIZATION.t("WE_NEW_WORLD"), "New World", failures, "fallback locale")
		_assert_equals(LOCALIZATION.t("WE_MISSING_KEY"), "WE_MISSING_KEY", failures, "missing key")
		LOCALIZATION.locale_override = ""
		LOCALIZATION.reset_cache()
		return failures


	func _assert_equals(actual: String, expected: String, failures: Array[String], label: String) -> void:
		if actual != expected:
			failures.append("%s: expected '%s', got '%s'" % [label, expected, actual])


## tests/authoring/test_world_preview_zoom.gd
class WorldPreviewZoomCase extends Node:
	## Zoomed-in preview must not clip the terrain inside the viewport.
	##
	## The preview layer used to size its clip container from the world origin, so at
	## high zoom the container's right/bottom edges landed inside the viewport and cut
	## the terrain off along a straight line (a rectangular bite growing up and to the
	## left). The container now covers the whole layer and the terrain instance carries
	## the world transform.

	const PREVIEW_PATH := "res://addons/world_editor/world_terrain_preview_layer.gd"
	const WORLD_DATA := preload("res://addons/platformer_kit/world/data/world_data.gd")
	const ROOM_DATA := preload("res://addons/platformer_kit/world/data/room_data.gd")
	const WORLD_TERRAIN := "user://zoom_test_world_terrain.tscn"
	const ROOM_TERRAIN := "user://zoom_test_room_terrain.tscn"
	const VIEWPORT := Vector2(800.0, 600.0)
	const ZOOM := 4.0


	func run() -> Array[String]:
		var failures: Array[String] = []
		var script := load(PREVIEW_PATH) as Script
		if script == null:
			return ["world terrain preview layer could not be loaded"]
		var tile_set := load("res://resources/tilesets/primordial_tileset.tres") as TileSet
		if tile_set == null:
			return ["primordial tileset could not be loaded"]
		if not _make_terrain_scene(WORLD_TERRAIN, tile_set, "WorldTerrain") or not _make_terrain_scene(
			ROOM_TERRAIN, tile_set, "RoomTerrain"
		):
			return ["could not build the preview terrain fixtures"]
		_assert_world_terrain_fills_the_layer(script, failures)
		_assert_room_preview_fills_the_layer(script, failures)
		DirAccess.remove_absolute(ProjectSettings.globalize_path(WORLD_TERRAIN))
		DirAccess.remove_absolute(ProjectSettings.globalize_path(ROOM_TERRAIN))
		return failures


	func _assert_world_terrain_fills_the_layer(script: Script, failures: Array[String]) -> void:
		var world: WorldData = WORLD_DATA.new()
		world.world_id = "zoom_test"
		world.terrain_scene_path = WORLD_TERRAIN
		var room: RoomData = ROOM_DATA.new()
		room.room_id = "room_a"
		room.room_size_chunks = Vector2i.ONE
		room.terrain_scene_path = ROOM_TERRAIN
		world.rooms.assign([room])
		world.set_room_origin_chunk("room_a", Vector2i(2, 1))

		var preview := script.new() as Control
		preview.size = VIEWPORT
		add_child(preview)
		# The origin sits up-left of the view, which is what broke the old clip rect.
		var center := Vector2(900.0, 700.0)
		preview.call("set_view_transform", center, ZOOM, VIEWPORT)
		preview.call("sync_world", world)
		var container := preview.get_node_or_null("WorldTerrain") as Control
		if container == null:
			failures.append("preview did not build the world terrain container")
			preview.free()
			return
		if container.position != Vector2.ZERO or container.size != VIEWPORT:
			failures.append(
				"world terrain clip container is not the whole layer: %s / %s"
				% [str(container.position), str(container.size)]
			)
		var instance := container.get_child(0) as Node2D
		if instance == null:
			failures.append("world terrain container has no terrain instance")
		elif not is_equal_approx(instance.scale.x, ZOOM) or not is_equal_approx(instance.scale.y, ZOOM):
			failures.append("world terrain instance is not scaled by the zoom: %s" % str(instance.scale))
		elif not instance.position.is_equal_approx((Vector2.ZERO - center) * ZOOM + VIEWPORT * 0.5):
			failures.append("world terrain instance is not placed by the view transform: %s" % str(instance.position))
		preview.free()


	func _assert_room_preview_fills_the_layer(script: Script, failures: Array[String]) -> void:
		var world: WorldData = WORLD_DATA.new()
		world.world_id = "zoom_test_rooms"
		var room: RoomData = ROOM_DATA.new()
		room.room_id = "room_a"
		room.room_size_chunks = Vector2i.ONE
		room.terrain_scene_path = ROOM_TERRAIN
		world.rooms.assign([room])
		world.set_room_origin_chunk("room_a", Vector2i(2, 1))

		var preview := script.new() as Control
		preview.size = VIEWPORT
		add_child(preview)
		var center := Vector2(900.0, 700.0)
		preview.call("set_view_transform", center, ZOOM, VIEWPORT)
		preview.call("sync_world", world)
		var container := preview.get_node_or_null("room_a") as Control
		if container == null:
			failures.append("preview did not build the fallback room container")
			preview.free()
			return
		if container.position != Vector2.ZERO or container.size != VIEWPORT:
			failures.append(
				"room preview clip container is not the whole layer: %s / %s"
				% [str(container.position), str(container.size)]
			)
		var instance := container.get_child(0) as Node2D
		if instance == null:
			failures.append("room preview container has no terrain instance")
		else:
			var world_origin := Vector2(RoomGrid.get_room_cell_rect(Vector2i(2, 1), Vector2i.ONE).position * 8)
			if not instance.position.is_equal_approx((world_origin - center) * ZOOM + VIEWPORT * 0.5):
				failures.append("room preview instance is not placed by the view transform: %s" % str(instance.position))
			if not is_equal_approx(instance.scale.x, ZOOM):
				failures.append("room preview instance is not scaled by the zoom")
		preview.free()


	func _make_terrain_scene(path: String, tile_set: TileSet, root_name: String) -> bool:
		var root := Node2D.new()
		root.name = root_name
		var terrain := Node2D.new()
		terrain.name = "Terrain"
		root.add_child(terrain)
		terrain.owner = root
		var layer := TileMapLayer.new()
		layer.name = "SolidTiles"
		layer.tile_set = tile_set
		terrain.add_child(layer)
		layer.owner = root
		layer.set_cell(Vector2i(0, 0), 0, Vector2i(1, 0))
		var scene := PackedScene.new()
		var pack_error := scene.pack(root)
		root.free()
		if pack_error != OK:
			return false
		return ResourceSaver.save(scene, path) == OK


## tests/authoring/test_world_canvas_selection.gd
class WorldCanvasSelectionCase extends Node:
	## Coverage for the World canvas selection model: box selection (intersection),
	## additive/toggle selection, group drag (one command) and delete/escape input.

	const CANVAS := preload("res://addons/world_editor/world_layout_canvas.gd")
	const WORLD := preload("res://addons/platformer_kit/world/data/world_data.gd")
	const ROOM := preload("res://addons/platformer_kit/world/data/room_data.gd")


	class FakeMain:
		extends Control

		var world_data: Resource
		var selected_room_id := ""
		var moves: Array = []
		var move_calls := 0

		func select_room(room_id: String) -> void:
			selected_room_id = room_id

		func move_rooms_by(delta: Vector2i) -> bool:
			move_calls += 1
			moves.append(delta)
			return true

		func move_room(room_id: String, origin: Vector2i) -> bool:
			move_calls += 1
			moves.append([room_id, origin])
			return true

		func update_zoom_label(_zoom: float) -> void:
			pass


	func run() -> Array[String]:
		var failures: Array[String] = []
		var main := FakeMain.new()
		main.world_data = _make_world()
		var canvas := CANVAS.new() as Control
		canvas.size = Vector2(800, 600)
		add_child(canvas)
		canvas.call("set_main_screen", main)
		canvas.call("focus_all")

		var alpha_rect: Rect2 = canvas.call("_room_rect", Vector2i(0, 0), Vector2i(2, 1))
		var beta_rect: Rect2 = canvas.call("_room_rect", Vector2i(3, 0), Vector2i(2, 1))

		canvas.call("box_select", alpha_rect.grow(-2.0), false)
		_assert_selection(canvas, ["alpha"], "alpha", failures, "single box")
		canvas.call("box_select", alpha_rect.merge(beta_rect).grow(-2.0), false)
		_assert_selection(canvas, ["alpha", "beta"], "alpha", failures, "both rooms box")
		canvas.call("box_select", alpha_rect.grow(-2.0), false)
		canvas.call("box_select", beta_rect.grow(-2.0), true)
		_assert_selection(canvas, ["alpha", "beta"], "alpha", failures, "additive box")
		canvas.call("_toggle_room", "beta")
		_assert_selection(canvas, ["alpha"], "alpha", failures, "toggle off")
		canvas.call("_toggle_room", "beta")
		_assert_selection(canvas, ["alpha", "beta"], "beta", failures, "toggle on")
		canvas.call("select_all")
		_assert_selection(canvas, ["alpha", "beta"], "alpha", failures, "select all")

		_assert_group_drag(canvas, main, alpha_rect, failures)
		_assert_input_signals(canvas, failures)

		canvas.free()
		main.free()
		return failures


	func _assert_group_drag(canvas: Control, main: FakeMain, alpha_rect: Rect2, failures: Array[String]) -> void:
		canvas.call("select_all")
		main.move_calls = 0
		main.moves.clear()
		var start := alpha_rect.get_center()
		var zoom := float(canvas.call("get_zoom"))
		var target := start + Vector2(320.0 * zoom, 0.0)
		if not bool(canvas.call("begin_room_drag", "alpha", start)):
			failures.append("group drag did not start")
			return
		canvas.call("update_room_drag", target)
		canvas.call("_commit_drag", target)
		if main.move_calls != 1:
			failures.append("group drag issued %d move calls instead of one" % main.move_calls)
		elif main.moves.is_empty() or main.moves[0] != Vector2i(1, 0):
			failures.append("group drag moved by %s instead of (1, 0)" % [main.moves])


	func _assert_input_signals(canvas: Control, failures: Array[String]) -> void:
		var deleted := [0]
		canvas.delete_requested.connect(func() -> void: deleted[0] += 1)
		var delete_event := InputEventKey.new()
		delete_event.keycode = KEY_DELETE
		delete_event.pressed = true
		canvas.call("_gui_input", delete_event)
		if deleted[0] != 1:
			failures.append("Delete key did not request a removal")
		canvas.call("select_all")
		var cleared := [false]
		canvas.selection_changed.connect(func(ids: Array, _primary: String) -> void:
			if ids.is_empty():
				cleared[0] = true
		)
		var escape_event := InputEventKey.new()
		escape_event.keycode = KEY_ESCAPE
		escape_event.pressed = true
		canvas.call("_gui_input", escape_event)
		if not cleared[0]:
			failures.append("Escape did not emit an empty selection")
		if not (canvas.call("get_selected_room_ids") as Array).is_empty():
			failures.append("Escape did not clear the canvas selection")


	func _assert_selection(
		canvas: Control,
		expected: Array,
		primary: String,
		failures: Array[String],
		label: String
	) -> void:
		var ids: Array = canvas.call("get_selected_room_ids")
		if ids != expected:
			failures.append("%s: selection was %s, expected %s" % [label, ids, expected])
		if String(canvas.call("get_primary_room_id")) != primary:
			failures.append("%s: primary was %s, expected %s" % [label, canvas.call("get_primary_room_id"), primary])


	func _make_world() -> Resource:
		var world := WORLD.new() as Resource
		for entry: Array in [["alpha", Vector2i(0, 0)], ["beta", Vector2i(3, 0)]]:
			var room := ROOM.new() as Resource
			room.room_id = String(entry[0])
			room.room_size_chunks = Vector2i(2, 1)
			world.rooms.append(room)
			world.set_room_origin_chunk(String(entry[0]), entry[1] as Vector2i)
		world.start_room_id = "alpha"
		return world


## tests/authoring/test_room_annotations.gd
class RoomAnnotationsCase extends Node:
	## Coverage for the World editor room annotation service: entity discovery,
	## transform accumulation, ids, caching and missing scenes.

	const ANNOTATIONS := preload("res://addons/world_editor/authoring/world/room_annotation_service.gd")
	const ROOM_DATA := preload("res://addons/platformer_kit/world/data/room_data.gd")
	const WORLD_DATA := preload("res://addons/platformer_kit/world/data/world_data.gd")
	const SPAWN := preload("res://addons/platformer_kit/world/entities/spawn_point.gd")
	const ENTRANCE := preload("res://addons/platformer_kit/world/entities/room_entrance.gd")
	const SAVE := preload("res://addons/platformer_kit/world/entities/save_point.gd")
	const CUSTOM := preload("res://addons/platformer_kit/world/entities/world_entity.gd")
	const DOOR := preload("res://addons/platformer_kit/world/entities/world_door.gd")
	const SCENE := "user://world_annotations.tscn"


	func run() -> Array[String]:
		var failures: Array[String] = []
		_build_scene()
		_assert_collects_anchors(failures)
		_assert_door_annotation(failures)
		_assert_cache_hits(failures)
		_assert_missing_scene(failures)
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SCENE))
		return failures


	func _assert_collects_anchors(failures: Array[String]) -> void:
		var service := ANNOTATIONS.new() as RoomAnnotationService
		var annotations := service.collect(_make_room())
		if annotations.size() != 5:
			failures.append("expected 5 annotations, got %d" % annotations.size())
			return
		_assert_annotation(annotations, RoomAnnotationService.TYPE_SPAWN, "start", Vector2(20, 12), failures)
		_assert_annotation(annotations, RoomAnnotationService.TYPE_ENTRANCE, "east", Vector2(52, 12), failures)
		_assert_annotation(annotations, RoomAnnotationService.TYPE_SAVE, "save_a", Vector2(28, 28), failures)
		_assert_annotation(annotations, RoomAnnotationService.TYPE_WORLD_ENTITY, "custom", Vector2(12, 36), failures)
		_assert_annotation(annotations, RoomAnnotationService.TYPE_DOOR, "door_a", Vector2(44, 40), failures)


	func _assert_door_annotation(failures: Array[String]) -> void:
		var service := ANNOTATIONS.new() as RoomAnnotationService
		var annotations := service.collect(_make_room())
		var door: Dictionary = {}
		for annotation: Dictionary in annotations:
			if String(annotation.get("id", "")) == "door_a":
				door = annotation
		if door.is_empty():
			failures.append("missing door annotation door_a")
			return
		if door.get("type", &"") != RoomAnnotationService.TYPE_DOOR:
			failures.append("door annotation was typed %s instead of door" % str(door.get("type", &"")))
		if door.get("type", &"") == RoomAnnotationService.TYPE_WORLD_ENTITY:
			failures.append("door annotation was typed world_entity")
		if int(door.get("door_kind", -1)) != DOOR.Kind.SHUTTLE:
			failures.append("door annotation lost its door_kind")
		if String(door.get("target_world_id", "")) != "shadow_world":
			failures.append("door annotation lost its target_world_id")
		if String(door.get("target_room_id", "")) != "room_shadow":
			failures.append("door annotation lost its target_room_id")
		if String(door.get("target_door_id", "")) != "door_b":
			failures.append("door annotation lost its target_door_id")


	func _assert_annotation(
		annotations: Array[Dictionary],
		type: StringName,
		id: String,
		position: Vector2,
		failures: Array[String]
	) -> void:
		for annotation: Dictionary in annotations:
			if annotation["type"] == type and annotation["id"] == id:
				if not (annotation["position"] as Vector2).is_equal_approx(position):
					failures.append("%s %s position was %s, expected %s" % [type, id, annotation["position"], position])
				return
		failures.append("missing annotation %s %s" % [type, id])


	func _assert_cache_hits(failures: Array[String]) -> void:
		var service := ANNOTATIONS.new() as RoomAnnotationService
		var calls := [0]
		service.load_provider = func(path: String) -> PackedScene:
			calls[0] += 1
			return ResourceLoader.load(path, "PackedScene") as PackedScene
		var room := _make_room()
		service.collect(room)
		service.collect(room)
		if int(calls[0]) != 1:
			failures.append("runtime scene was loaded %d times for an unchanged file" % int(calls[0]))


	func _assert_missing_scene(failures: Array[String]) -> void:
		var service := ANNOTATIONS.new() as RoomAnnotationService
		var room := _make_room()
		room.scene_path = "user://world_annotations_missing.tscn"
		if not service.collect(room).is_empty():
			failures.append("missing runtime scene returned annotations")


	func _make_room() -> RoomData:
		var room := ROOM_DATA.new() as RoomData
		room.room_id = "annotations_test"
		room.scene_path = SCENE
		return room


	func _build_scene() -> void:
		var root := Node2D.new()
		root.name = "Runtime"
		var entities := Node2D.new()
		entities.name = "Entities"
		entities.position = Vector2(4, 4)
		root.add_child(entities)

		var spawn := SPAWN.new() as SpawnPoint
		spawn.name = "Spawn"
		spawn.spawn_id = "start"
		spawn.position = Vector2(16, 8)
		entities.add_child(spawn)

		var entrance := ENTRANCE.new() as RoomEntrance
		entrance.name = "Door"
		entrance.entity_id = "east"
		entrance.position = Vector2(48, 8)
		entities.add_child(entrance)

		var save := SAVE.new() as SavePoint
		save.name = "Save"
		save.entity_id = "save_a"
		save.position = Vector2(24, 24)
		entities.add_child(save)

		var custom := CUSTOM.new() as WorldEntity
		custom.name = "Custom"
		custom.entity_id = "custom"
		custom.position = Vector2(8, 32)
		entities.add_child(custom)

		var target_world := WORLD_DATA.new() as WorldData
		target_world.world_id = "shadow_world"
		var door := DOOR.new() as WorldDoor
		door.name = "ShuttleDoor"
		door.entity_id = "door_a"
		door.door_kind = DOOR.Kind.SHUTTLE
		door.target_world = target_world
		door.target_room_id = "room_shadow"
		door.target_door_id = "door_b"
		door.position = Vector2(40, 36)
		entities.add_child(door)

		entities.owner = root
		for child: Node in entities.get_children():
			child.owner = root

		var packed := PackedScene.new()
		packed.pack(root)
		ResourceSaver.save(packed, SCENE)
		root.free()


## tests/authoring/test_world_terrain_preview_layer.gd
class WorldTerrainPreviewLayerCase extends Node:
	const PREVIEW_PATH := "res://addons/world_editor/world_terrain_preview_layer.gd"
	const TERRAIN_PATH := "user://terrain_preview_fixture.tscn"
	const WORLD_DATA := preload("res://addons/platformer_kit/world/data/world_data.gd")
	const ROOM_DATA := preload("res://addons/platformer_kit/world/data/room_data.gd")
	const LAYER_NAMES: Array[String] = ["BackTiles", "SolidTiles", "GlassTiles", "VisionBlockTiles", "DetailTiles", "MarkerTiles"]


	func run() -> Array[String]:
		var failures: Array[String] = []
		_remove_fixture()
		if _save_fixture() != OK:
			return ["could not save terrain preview fixture"]
		var script := load(PREVIEW_PATH) as Script
		if script == null or not script.can_instantiate():
			_remove_fixture()
			return ["world terrain preview layer could not be loaded"]
		var world: Resource = WORLD_DATA.new()
		var room: Resource = ROOM_DATA.new()
		room.room_id = "room_a"
		room.terrain_scene_path = TERRAIN_PATH
		room.room_size_chunks = Vector2i(2, 1)
		world.rooms.assign([room])
		world.set_room_origin_chunk("room_a", Vector2i(-1, 2))
		var preview: Control = script.new() as Control
		preview.call("set_view_transform", Vector2.ZERO, 1.0, Vector2(640, 360))
		preview.call("sync_world", world)
		var container: Control = preview.get_node_or_null("room_a") as Control
		if container == null:
			failures.append("terrain preview did not create a room container")
		else:
			# The clip container spans the layer; the terrain instance carries the
			# placement transform, so zooming in can never clip along a straight edge.
			if container.position != Vector2.ZERO:
				failures.append("terrain preview container did not span the layer")
			if container.mouse_filter != Control.MOUSE_FILTER_IGNORE or not container.clip_contents:
				failures.append("terrain preview container was not clipped and input-transparent")
			if container.z_index < 0:
				failures.append("terrain preview was rendered behind the opaque canvas background")
			var terrain := container.get_child(0) as Node
			if terrain == null:
				failures.append("terrain preview container did not instantiate generated terrain")
			else:
				if not (terrain as Node2D).position.is_equal_approx(Vector2(-320, 360) + Vector2(320, 180)):
					failures.append("terrain preview did not use the placement pixel origin")
				if not terrain.visible:
					failures.append("terrain preview root was hidden by layer filtering")
				for layer_name: String in LAYER_NAMES:
					var layer := terrain.get_node_or_null("Terrain/%s" % layer_name) as TileMapLayer
					if layer == null:
						continue
					var should_show := layer_name != "MarkerTiles"
					if layer.visible != should_show:
						failures.append("terrain preview visibility was wrong for %s" % layer_name)
					if layer.process_mode != Node.PROCESS_MODE_DISABLED:
						failures.append("terrain preview did not disable processing for %s" % layer_name)
				var extra := terrain.get_node_or_null("Terrain/Extra") as CanvasItem
				if extra != null and extra.visible:
					failures.append("terrain preview left an extra terrain CanvasItem visible")
		preview.free()
		_remove_fixture()
		return failures


	func _save_fixture() -> Error:
		var root := Node2D.new()
		root.name = "TerrainPreviewFixture"
		var background := Node2D.new()
		background.name = "Background"
		root.add_child(background)
		background.owner = root
		var terrain := Node2D.new()
		terrain.name = "Terrain"
		root.add_child(terrain)
		terrain.owner = root
		for layer_name: String in LAYER_NAMES:
			var layer := TileMapLayer.new()
			layer.name = layer_name
			terrain.add_child(layer)
			layer.owner = root
		var extra := Node2D.new()
		extra.name = "Extra"
		terrain.add_child(extra)
		extra.owner = root
		var packed := PackedScene.new()
		var pack_error := packed.pack(root)
		root.free()
		return pack_error if pack_error != OK else ResourceSaver.save(packed, TERRAIN_PATH)


	func _remove_fixture() -> void:
		if FileAccess.file_exists(TERRAIN_PATH):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(TERRAIN_PATH))


func run() -> Array[String]:
	var failures: Array[String] = []
	failures.append_array(_run_case(RoomPreviewSpawnAutoCase.new()))
	failures.append_array(_run_case(LevelTemplateContractCase.new()))
	failures.append_array(_run_case(WorldRoomDrawCase.new()))
	failures.append_array(_run_case(ComponentsGalleryCase.new()))
	failures.append_array(_run_case(WorldEditorMainScreenCase.new()))
	failures.append_array(_run_case(WorldEditorLocalizationCase.new()))
	failures.append_array(_run_case(WorldPreviewZoomCase.new()))
	failures.append_array(_run_case(WorldCanvasSelectionCase.new()))
	failures.append_array(_run_case(RoomAnnotationsCase.new()))
	failures.append_array(_run_case(WorldTerrainPreviewLayerCase.new()))
	return failures


func _run_case(test: Node) -> Array[String]:
	add_child(test)
	var result: Array = test.call("run")
	test.queue_free()
	var failures: Array[String] = []
	failures.assign(result)
	return failures
