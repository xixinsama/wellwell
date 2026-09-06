extends Node

const ROOM_AUTHORING_CONTRACT: Script = preload("res://scripts/authoring/room_authoring_contract.gd")
const ROOM_BAKER: Script = preload("res://scripts/authoring/room_baker.gd")

const TEMPLATE_PATH := "res://scenes/templates/level_template.tscn"
const LEVEL_ZERO_PATH := "res://scenes/levels/level_0.tscn"
const LAYER_NAMES: Array[String] = [
	"BackTiles",
	"SolidTiles",
	"GlassTiles",
	"VisionBlockTiles",
	"DetailTiles",
	"MarkerTiles",
]


func run() -> Array[String]:
	var failures: Array[String] = []
	var template_scene := load(TEMPLATE_PATH) as PackedScene
	var level_scene := load(LEVEL_ZERO_PATH) as PackedScene
	if template_scene == null or level_scene == null:
		failures.append("template or level_0 scene could not be loaded")
		return failures

	var template_root := template_scene.instantiate()
	var level_root := level_scene.instantiate()
	_assert_contract(template_root, "template", failures)
	_assert_contract(level_root, "level_0", failures)
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
	if String(root.get("room_id")) != "level_0":
		failures.append("level_0 room_id override is missing")
	if String(root.get("display_name")).is_empty():
		failures.append("level_0 display_name override is missing")
	if root.get("room_size_chunks") != Vector2i.ONE:
		failures.append("level_0 validation room must remain one chunk")
	if String(root.get("preview_spawn_id")) != "start":
		failures.append("level_0 preview spawn must be start")
	var start_spawn := root.get_node_or_null("RoomContent/Entities/StartSpawn")
	if not start_spawn is SpawnPoint:
		failures.append("level_0 StartSpawn must be a SpawnPoint")
	elif String(start_spawn.get("spawn_id")) != String(root.get("preview_spawn_id")):
		failures.append("level_0 StartSpawn id must match preview_spawn_id")
	var solid := root.get_node("RoomContent/Terrain/SolidTiles") as TileMapLayer
	var glass := root.get_node("RoomContent/Terrain/GlassTiles") as TileMapLayer
	if solid.get_used_cells().is_empty():
		failures.append("level_0 validation room has no solid tiles")
	if glass.get_used_cells().is_empty():
		failures.append("level_0 validation room has no glass tiles")


func _assert_preview_and_stage(root: Node, failures: Array[String]) -> void:
	add_child(root)
	var controller := root.get_node_or_null("RoomPreviewController")
	if controller == null:
		failures.append("level_0 preview controller is missing")
	else:
		var snapshot: RefCounted = controller.call("get_preview_snapshot")
		if snapshot == null:
			failures.append("level_0 preview controller did not initialize on scene ready")
		elif String(snapshot.get("current_room_id")) != "level_0":
			failures.append("level_0 preview snapshot has the wrong room id")
		elif int(snapshot.get("slot")) != 0:
			failures.append("level_0 preview snapshot must use in-memory slot 0")
	var baker: RefCounted = ROOM_BAKER.new()
	var staged: Dictionary = baker.stage(root, LEVEL_ZERO_PATH)
	if not staged.get("ok", false):
		failures.append("level_0 could not stage: %s" % staged.get("errors", []))
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
