extends Control

## Development runner for the loop world: starts it directly with the debug
## overlay on, so the whole ring can be walked without going through the menu.

const SAVE_SNAPSHOT := preload("res://addons/platformer_kit/save/save_snapshot.gd")
const PROGRESSION_CONTEXT := preload("res://addons/metroidvania_kit/progression/progression_context.gd")
const MAP_DISCOVERY := preload("res://addons/metroidvania_kit/map/discovery/map_discovery.gd")
const MARKER_REGISTRY := preload("res://addons/metroidvania_kit/map/markers/marker_registry.gd")
const WORLD_STATE := preload("res://addons/metroidvania_kit/world_state/metroidvania_world_state.gd")
const FAST_TRAVEL_REGISTRY := preload("res://addons/metroidvania_kit/fast_travel/fast_travel_registry.gd")

@onready var world_root: Node = $SubViewportContainer/SubViewport/WorldRoot


func _ready() -> void:
	var fog := world_root.get_node_or_null("FogOfWar")
	var crumble := world_root.get_node_or_null("CrumbleRuntime")
	var water := world_root.get_node_or_null("WaterField")
	var water_grid := world_root.get_node_or_null("WaterGrid")
	var atmosphere := world_root.get_node_or_null("Atmosphere")
	var light_field := world_root.get_node_or_null("LightField")
	if fog != null:
		world_root.call("register_room_extension", fog)
	if crumble != null:
		world_root.call("register_room_extension", crumble)
	if water != null:
		world_root.call("register_room_extension", water)
	if water_grid != null:
		world_root.call("register_room_extension", water_grid)
	if atmosphere != null:
		world_root.call("register_room_extension", atmosphere)
	if light_field != null:
		world_root.call("register_room_extension", light_field)
	if world_root.has_method("bind_settings_source"):
		world_root.call("bind_settings_source", GlobalSettings)
	_wire_persistence_bridge(fog)
	var snapshot: RefCounted = SAVE_SNAPSHOT.new()
	snapshot.slot = 0
	var started := bool(world_root.call("start_selected_snapshot", snapshot, world_root.get("world_data")))
	if not started:
		push_error("loop world start failed: %s" % [world_root.call("get_last_start_errors")])


func _wire_persistence_bridge(fog: Node) -> void:
	var bridge := world_root.get_node_or_null("MetroidvaniaPersistenceBridge")
	if bridge == null or fog == null:
		return
	bridge.call(
		"configure",
		PROGRESSION_CONTEXT.new(),
		MAP_DISCOVERY.new(),
		MARKER_REGISTRY.new(),
		WORLD_STATE.new(),
		FAST_TRAVEL_REGISTRY.new(),
		fog
	)
	if world_root.has_method("bind_persistence_source"):
		world_root.call("bind_persistence_source", bridge)
