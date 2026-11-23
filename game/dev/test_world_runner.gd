extends Control

## Development runner: starts a world directly, without the menu, in the same
## pixel viewport as the game. `start_room_override` selects a room inside that
## world, which is how the fluid labs launch their room.
##
## Run one by opening its scene under `scenes/levels/test_world/runners/`.

@export var start_room_override := ""

@onready var world_root: WorldSession = $SubViewportContainer/SubViewport/WorldRoot


func _ready() -> void:
	var fog := world_root.get_node_or_null("FogOfWar") as FogOfWar
	var overlay := world_root.get_node_or_null("DebugOverlay") as PlatformerDebugOverlay2D
	if overlay != null:
		overlay.set_enabled(false)
	for extension: Node in [
		fog,
		world_root.get_node_or_null("CrumbleRuntime"),
		world_root.get_node_or_null("WaterField"),
		world_root.get_node_or_null("WaterGrid"),
		world_root.get_node_or_null("Atmosphere"),
		world_root.get_node_or_null("LightField"),
	]:
		if extension != null:
			world_root.register_room_extension(extension)
	world_root.bind_settings_source(GlobalSettings)
	_wire_persistence_bridge(fog)
	var snapshot := SaveSnapshot.new()
	snapshot.slot = 0
	var world: WorldData = world_root.world_data
	if world != null and not start_room_override.is_empty():
		var overridden := world.duplicate() as WorldData
		var start_room: RoomData = overridden.get_room(start_room_override)
		if start_room != null:
			overridden.start_room_id = start_room_override
			if not start_room.spawn_ids.is_empty():
				overridden.start_spawn_id = start_room.spawn_ids[0]
			world = overridden
	if not world_root.start_selected_snapshot(snapshot, world):
		push_error("test world start failed: %s" % [world_root.get_last_start_errors()])


## The runner has no save file, but the exploration bridge still accumulates every
## visited room in memory. Without it the map would forget rooms after a
## transition, because the fog only holds the loaded room.
func _wire_persistence_bridge(fog: FogOfWar) -> void:
	var bridge := world_root.get_node_or_null(
		"MetroidvaniaPersistenceBridge"
	) as MetroidvaniaPersistenceBridge
	if bridge == null or fog == null:
		return
	bridge.configure(
		ProgressionContext.new(),
		MapDiscovery.new(),
		MarkerRegistry.new(),
		MetroidvaniaWorldState.new(),
		FastTravelRegistry.new(),
		fog
	)
	world_root.bind_persistence_source(bridge)
