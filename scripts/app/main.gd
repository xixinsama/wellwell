extends Control
class_name Main

const SAFE_SIZE: Vector2i = Vector2i(320, 180)
const VIEWPORT_SIZE: Vector2i = Vector2i(322, 182)
const MIN_SCALE: int = 1
const PROGRESSION_CONTEXT := preload("res://addons/metroidvania_kit/progression/progression_context.gd")
const MAP_DISCOVERY := preload("res://addons/metroidvania_kit/map/discovery/map_discovery.gd")
const MARKER_REGISTRY := preload("res://addons/metroidvania_kit/map/markers/marker_registry.gd")
const MAP_RUNTIME := preload("res://addons/metroidvania_kit/map/runtime/map_runtime.gd")
const MAP_TRACKER := preload("res://addons/metroidvania_kit/map/runtime/map_tracker.gd")
const REVEAL_ADJACENT := preload("res://addons/metroidvania_kit/map/discovery/rules/reveal_adjacent_rooms.gd")
const WORLD_STATE := preload("res://addons/metroidvania_kit/world_state/metroidvania_world_state.gd")
const FAST_TRAVEL_REGISTRY := preload("res://addons/metroidvania_kit/fast_travel/fast_travel_registry.gd")
const MAIN_MAP := preload("res://game/data/maps/main_map.tres")

@onready var viewport_container: SubViewportContainer = $SubViewportContainer
@onready var sub_viewport: SubViewport = $SubViewportContainer/SubViewport


func _ready() -> void:
    get_viewport().size_changed.connect(setup_viewport_scale)
    setup_viewport_scale()

    Globals.SVC = viewport_container
    var world_root := sub_viewport.get_node_or_null("WorldRoot")
    if world_root != null:
        var fog := world_root.get_node_or_null("FogOfWar")
        var persistence_bridge := world_root.get_node_or_null("MetroidvaniaPersistenceBridge")
        if fog != null and world_root.has_method("register_room_extension"):
            world_root.call("register_room_extension", fog)
        if persistence_bridge != null:
            _configure_metroidvania_runtime(world_root, persistence_bridge, fog)
            persistence_bridge.call("bind_save_manager", SaveManager)
        if world_root.has_method("bind_persistence_source"):
            world_root.call("bind_persistence_source", SaveManager)
        if world_root.has_method("bind_settings_source"):
            world_root.call("bind_settings_source", GlobalSettings)


func _configure_metroidvania_runtime(world_root: Node, persistence_bridge: Node, fog: Node) -> void:
    var progression: RefCounted = PROGRESSION_CONTEXT.new()
    var discovery: RefCounted = MAP_DISCOVERY.new()
    var markers: RefCounted = MARKER_REGISTRY.new()
    var world_state: RefCounted = WORLD_STATE.new()
    var fast_travel: RefCounted = FAST_TRAVEL_REGISTRY.new()
    var map_runtime: RefCounted = MAP_RUNTIME.new()
    map_runtime.call("configure", MAIN_MAP, discovery, markers)
    var tracker: Node = MAP_TRACKER.new()
    tracker.name = "MapTracker"
    world_root.add_child(tracker)
    var rules: Array[Resource] = [REVEAL_ADJACENT.new()]
    tracker.call("configure", map_runtime, rules)
    var world_runtime := world_root.get_node_or_null("WorldRuntime")
    if world_runtime != null and world_runtime.has_signal("current_room_changed"):
        world_runtime.connect("current_room_changed", func(room_id: String) -> void:
            tracker.call("track_room", StringName(room_id))
        )
    var player := world_root.get_node_or_null("Player")
    var loadout := player.get_node_or_null("AbilityLoadout") if player != null else null
    if loadout != null and loadout.has_method("bind_progression"):
        loadout.call("bind_progression", progression)
        if persistence_bridge.has_signal("state_restored"):
            persistence_bridge.connect(
                "state_restored",
                Callable(loadout, "synchronize_unlocked_abilities")
            )
    persistence_bridge.call("configure", progression, discovery, markers, world_state, fast_travel, fog)


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
