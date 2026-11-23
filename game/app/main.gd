extends Control
class_name Main

## Application shell: scales the pixel SubViewport, then wires the active world to
## the project's room extensions and the Metroidvania map runtime. Every node it
## touches is typed, so a renamed or re-signatured collaborator fails at compile
## time instead of silently skipping its `call()`.

const SAFE_SIZE: Vector2i = Vector2i(320, 180)
const VIEWPORT_SIZE: Vector2i = Vector2i(322, 182)
const MIN_SCALE: int = 1

var _map_runtime: MapRuntime
var _map_tracker: MapTracker
var _map_discovery: MapDiscovery
var _map_markers: MarkerRegistry

@onready var viewport_container: SubViewportContainer = $SubViewportContainer
@onready var sub_viewport: SubViewport = $SubViewportContainer/SubViewport
@onready var interaction_prompt: InteractionPrompt = $HUD/InteractionPrompt


func _ready() -> void:
	get_viewport().size_changed.connect(setup_viewport_scale)
	setup_viewport_scale()

	Globals.SVC = viewport_container
	var world_root := sub_viewport.get_node_or_null("WorldRoot") as WorldSession
	if world_root == null:
		return
	var player := world_root.get_node_or_null("Player") as Node2D
	if interaction_prompt != null and player != null:
		interaction_prompt.bind_actor(player)
	var fog := world_root.get_node_or_null("FogOfWar") as FogOfWar
	_register_room_extension(world_root, fog)
	_register_room_extension(world_root, world_root.get_node_or_null("CrumbleRuntime"))
	_register_room_extension(world_root, world_root.get_node_or_null("WaterField"))
	_register_room_extension(world_root, world_root.get_node_or_null("WaterGrid"))
	_register_room_extension(world_root, world_root.get_node_or_null("Atmosphere"))
	_register_room_extension(world_root, world_root.get_node_or_null("LightField"))
	var bridge := world_root.get_node_or_null(
		"MetroidvaniaPersistenceBridge"
	) as MetroidvaniaPersistenceBridge
	if bridge != null:
		_configure_metroidvania_runtime(world_root, bridge, fog)
		bridge.bind_save_manager(SaveManager)
	world_root.bind_persistence_source(SaveManager)
	world_root.bind_settings_source(GlobalSettings)
	if not world_root.world_ready.is_connected(_on_world_ready):
		world_root.world_ready.connect(_on_world_ready)


func _register_room_extension(world_root: WorldSession, extension: Node) -> void:
	if extension != null:
		world_root.register_room_extension(extension)


## The map model is rebuilt from the world the player actually started, so it can
## never drift from the level placement or the baked terrain.
func _on_world_ready() -> void:
	var world_root := sub_viewport.get_node_or_null("WorldRoot") as WorldSession
	if world_root == null:
		return
	var world := world_root.world_data
	var collectibles := get_node_or_null("/root/Collectibles")
	if world != null and collectibles != null and collectibles.has_method("scan_world"):
		collectibles.call("scan_world", world)
	if _map_runtime == null:
		return
	var definition := MapDefinitionBuilder.from_world(world)
	if definition != null:
		_map_runtime.configure(definition, _map_discovery, _map_markers)


func _configure_metroidvania_runtime(
	world_root: WorldSession,
	persistence_bridge: MetroidvaniaPersistenceBridge,
	fog: FogOfWar
) -> void:
	var progression := ProgressionContext.new()
	var discovery := MapDiscovery.new()
	var markers := MarkerRegistry.new()
	var world_state := MetroidvaniaWorldState.new()
	var fast_travel := FastTravelRegistry.new()
	var definition := MapDefinitionBuilder.from_world(world_root.world_data)
	if definition == null:
		return
	_map_discovery = discovery
	_map_markers = markers
	_map_runtime = MapRuntime.new()
	_map_runtime.configure(definition, discovery, markers)
	var tracker := MapTracker.new()
	tracker.name = "MapTracker"
	world_root.add_child(tracker)
	var rules: Array[Resource] = [RevealAdjacentRooms.new()]
	tracker.configure(_map_runtime, rules)
	_map_tracker = tracker
	var world_runtime := world_root.get_node_or_null("WorldRuntime") as WorldRuntime
	if world_runtime != null:
		world_runtime.current_room_changed.connect(
			func(room_id: String) -> void:
				tracker.track_room(StringName(room_id))
		)
	var player := world_root.get_node_or_null("Player")
	var loadout := player.get_node_or_null("AbilityLoadout") as PlayerAbilityLoadout if player != null else null
	if loadout != null:
		loadout.bind_progression(progression)
		persistence_bridge.state_restored.connect(loadout.synchronize_unlocked_abilities)
	persistence_bridge.configure(progression, discovery, markers, world_state, fast_travel, fog)


func setup_viewport_scale() -> void:
	var window_size: Vector2 = get_viewport_rect().size
	var scale_x: int = floori(window_size.x / SAFE_SIZE.x)
	var scale_y: int = floori(window_size.y / SAFE_SIZE.y)
	var integer_scale: int = maxi(MIN_SCALE, mini(scale_x, scale_y))
	var display_size: Vector2 = Vector2(VIEWPORT_SIZE) * integer_scale
	viewport_container.custom_minimum_size = display_size
	viewport_container.size = display_size
	viewport_container.position = ((window_size - display_size) * 0.5).round()
	viewport_container.stretch = true
	viewport_container.stretch_shrink = integer_scale
