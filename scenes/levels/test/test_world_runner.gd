extends Control

## Development runner: starts the exploration test world directly, without the
## main menu, with the same pixel viewport as the game. Run this scene to test
## fog zones and crumble tiles after baking the source rooms.

const SAVE_SNAPSHOT := preload("res://addons/platformer_kit/save/save_snapshot.gd")
const PROGRESSION_CONTEXT := preload("res://addons/metroidvania_kit/progression/progression_context.gd")
const MAP_DISCOVERY := preload("res://addons/metroidvania_kit/map/discovery/map_discovery.gd")
const MARKER_REGISTRY := preload("res://addons/metroidvania_kit/map/markers/marker_registry.gd")
const WORLD_STATE := preload("res://addons/metroidvania_kit/world_state/metroidvania_world_state.gd")
const FAST_TRAVEL_REGISTRY := preload("res://addons/metroidvania_kit/fast_travel/fast_travel_registry.gd")

## Optional room id to start in instead of the world's own start room. Used by
## the gas lab runner, which reuses the same test world.
@export var start_room_override := ""

@onready var world_root: Node = $SubViewportContainer/SubViewport/WorldRoot


func _ready() -> void:
	var fog := world_root.get_node_or_null("FogOfWar")
	var crumble := world_root.get_node_or_null("CrumbleRuntime")
	var water := world_root.get_node_or_null("WaterField")
	var water_grid := world_root.get_node_or_null("WaterGrid")
	var atmosphere := world_root.get_node_or_null("Atmosphere")
	var light_field := world_root.get_node_or_null("LightField")
	var overlay := world_root.get_node_or_null("DebugOverlay")
	if overlay != null and overlay.has_method("set_enabled"):
		overlay.call("set_enabled", false)
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
	var world: WorldData = world_root.get("world_data") as WorldData
	if world != null and not start_room_override.is_empty():
		var overridden := world.duplicate() as WorldData
		var start_room: RoomData = overridden.get_room(start_room_override)
		if start_room != null:
			overridden.start_room_id = start_room_override
			if not start_room.spawn_ids.is_empty():
				overridden.start_spawn_id = start_room.spawn_ids[0]
			world = overridden
	var started := bool(world_root.call("start_selected_snapshot", snapshot, world))
	if not started:
		push_error("test world start failed: %s" % [world_root.call("get_last_start_errors")])


## The runner has no save file, but the exploration bridge still accumulates every
## visited room in memory. Without it the map would forget rooms after a
## transition, because the fog only holds the loaded room.
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
