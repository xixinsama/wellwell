extends Control

## Development runner: starts the exploration test world directly, without the
## main menu, with the same pixel viewport as the game. Run this scene to test
## fog zones and crumble tiles after baking the source rooms.

const SAVE_SNAPSHOT := preload("res://addons/platformer_kit/save/save_snapshot.gd")

## Optional room id to start in instead of the world's own start room. Used by
## the gas lab runner, which reuses the same test world.
@export var start_room_override := ""

@onready var world_root: Node = $SubViewportContainer/SubViewport/WorldRoot


func _ready() -> void:
	var fog := world_root.get_node_or_null("FogOfWar")
	var crumble := world_root.get_node_or_null("CrumbleRuntime")
	var water := world_root.get_node_or_null("WaterField")
	var atmosphere := world_root.get_node_or_null("Atmosphere")
	var overlay := world_root.get_node_or_null("DebugOverlay")
	if overlay != null and overlay.has_method("set_enabled"):
		overlay.call("set_enabled", false)
	if fog != null:
		world_root.call("register_room_extension", fog)
	if crumble != null:
		world_root.call("register_room_extension", crumble)
	if water != null:
		world_root.call("register_room_extension", water)
	if atmosphere != null:
		world_root.call("register_room_extension", atmosphere)
	if world_root.has_method("bind_settings_source"):
		world_root.call("bind_settings_source", GlobalSettings)
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
