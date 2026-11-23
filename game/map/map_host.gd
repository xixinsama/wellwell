class_name MapHost
extends Node

## Owns the always-on minimap and the full-screen map. The map model is built
## from the world the game is actually running, so nothing about the map is
## authored by hand.

const DEFINITION_BUILDER: Script = preload("res://addons/metroidvania_kit/map/data/map_definition_builder.gd")
const MAP_EXPLORATION: Script = preload("res://addons/metroidvania_kit/map/runtime/map_exploration.gd")
const MAP_EXPLORATION_SOURCE: Script = preload("res://game/map/map_exploration_source.gd")
const MAP_SCREEN: Script = preload("res://addons/metroidvania_kit/map/ui/map_screen.gd")
const MAP_MINIMAP: Script = preload("res://addons/metroidvania_kit/map/ui/map_minimap.gd")

@export var world_root_path: NodePath = NodePath("../../SubViewportContainer/SubViewport/WorldRoot")

var _world_root: Node
var _player: Node2D
var _runtime: Node
var _source: Object
var _definition: Resource
var _exploration: MapExploration
var _screen: MapScreen
var _minimap: MapMinimap


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	_wire_world()
	# Only build the map once a world is actually running, so it never appears
	# over the main menu.
	if _runtime != null and _runtime.has_method("get_current_room_id"):
		if not String(_runtime.call("get_current_room_id")).is_empty():
			bind_world(_world_root.get("world_data"))


## Builds the map model for a world. Returns false when the world is not loaded.
func bind_world(world: Resource) -> bool:
	if world == null or _screen == null:
		return false
	_definition = DEFINITION_BUILDER.from_world(world)
	if _definition == null:
		return false
	_exploration = MAP_EXPLORATION.new()
	_screen.bind(_definition, _exploration, _source, _player)
	_minimap.bind(_definition, _exploration, _source, _player, _runtime)
	return true


func get_definition() -> Resource:
	return _definition


func get_screen() -> MapScreen:
	return _screen


func get_minimap() -> MapMinimap:
	return _minimap


func _build_ui() -> void:
	_screen = MAP_SCREEN.new()
	_screen.name = "MapScreen"
	add_child(_screen)
	_minimap = MAP_MINIMAP.new()
	_minimap.name = "Minimap"
	add_child(_minimap)


func _wire_world() -> void:
	_world_root = get_node_or_null(world_root_path)
	if _world_root == null:
		return
	_player = _world_root.get_node_or_null("Player") as Node2D
	_runtime = _world_root.get_node_or_null("WorldRuntime")
	var bridge := _world_root.get_node_or_null("MetroidvaniaPersistenceBridge")
	var fog := _world_root.get_node_or_null("FogOfWar")
	if bridge != null or fog != null:
		var source: MapExplorationSource = MAP_EXPLORATION_SOURCE.new()
		source.bridge = bridge
		source.fog = fog
		_source = source
	else:
		_source = _world_root
	if _world_root.has_signal("world_ready"):
		_world_root.connect("world_ready", _on_world_ready)
	_screen.style_changed.connect(_on_style_changed)
	_screen.closed.connect(_on_screen_closed)
	_screen.opened.connect(_on_screen_opened)


func _on_screen_opened() -> void:
	_minimap.set_suppressed(true)


func _on_world_ready() -> void:
	bind_world(_world_root.get("world_data"))


func _on_style_changed(style: String) -> void:
	_minimap.set_style(style)


func _on_screen_closed() -> void:
	_minimap.set_suppressed(false)
	_minimap.set_style(_screen.get_style())
