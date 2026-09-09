@tool
class_name WorldTerrainPreviewLayer
extends Control

const CHUNK_PIXELS := Vector2(320, 180)
const VISIBLE_TILE_LAYERS: Array[String] = [
    "BackTiles", "SolidTiles", "GlassTiles", "VisionBlockTiles", "DetailTiles"
]

var preview_errors: Dictionary = {}
var _world: WorldData
var _room_containers: Dictionary[String, Control] = {}
var _room_scene_paths: Dictionary[String, String] = {}
var _drag_origins: Dictionary[String, Vector2i] = {}
var _view_center_world := Vector2.ZERO
var _view_zoom := 1.0
var _viewport_size := Vector2.ZERO


func _ready() -> void:
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    queue_redraw()


func _draw() -> void:
    draw_rect(Rect2(Vector2.ZERO, size), Color(0.106, 0.114, 0.129, 0.0), true)


func set_view_transform(center_world: Vector2, zoom: float, viewport_size: Vector2) -> void:
    _view_center_world = center_world
    _view_zoom = zoom
    _viewport_size = viewport_size
    for room_id: String in _room_containers:
        _update_room_container(room_id)


func sync_world(world: WorldData) -> void:
    if _world != world:
        _clear_previews()
    _world = world
    if _world == null:
        return
    for room_id: String in _room_containers.keys():
        if not _world.has_room(room_id):
            remove_room(room_id)
    for room_id: String in _world.get_room_ids():
        var room: Resource = _world.get_room(room_id)
        if not _room_containers.has(room_id) or _room_scene_paths.get(room_id, "") != room.terrain_scene_path:
            remove_room(room_id)
            _refresh_room_internal(room_id)
        else:
            _update_room_container(room_id)


func refresh_room(world: WorldData, room_id: String) -> void:
    if _world != world:
        sync_world(world)
        return
    remove_room(room_id)
    _refresh_room_internal(room_id)


func remove_room(room_id: String) -> void:
    var container: Control = _room_containers.get(room_id, null)
    if container != null and is_instance_valid(container):
        container.free()
    _room_containers.erase(room_id)
    _room_scene_paths.erase(room_id)
    _drag_origins.erase(room_id)
    preview_errors.erase(room_id)


func set_drag_origin(room_id: String, origin_or_null: Variant) -> void:
    if origin_or_null == null:
        _drag_origins.erase(room_id)
    else:
        _drag_origins[room_id] = Vector2i(origin_or_null)
    _update_room_container(room_id)


func clear_previews() -> void:
    _clear_previews()


func get_preview_room_ids() -> Array[String]:
    var result: Array[String] = []
    result.assign(_room_containers.keys())
    result.sort()
    return result


func get_preview_errors() -> Dictionary:
    return preview_errors.duplicate()


func _refresh_room_internal(room_id: String) -> void:
    if _world == null or not _world.has_room(room_id):
        return
    var room: Resource = _world.get_room(room_id)
    var scene := _load_terrain_scene(room)
    if scene == null:
        preview_errors[room_id] = "terrain scene could not be loaded: %s" % room.terrain_scene_path
        return
    var instance := scene.instantiate() as Node2D
    if instance == null:
        preview_errors[room_id] = "terrain scene root must be Node2D"
        return
    _configure_preview_tree(instance)
    var container := Control.new()
    container.name = room_id
    container.mouse_filter = Control.MOUSE_FILTER_IGNORE
    container.clip_contents = true
    # Render terrain after the canvas background; this layer has no opaque fill.
    container.z_index = 0
    add_child(container)
    container.add_child(instance)
    _room_containers[room_id] = container
    _room_scene_paths[room_id] = room.terrain_scene_path
    _update_room_container(room_id)


func _load_terrain_scene(room: Resource) -> PackedScene:
    if room == null or room.terrain_scene_path.is_empty():
        return null
    if not ResourceLoader.exists(room.terrain_scene_path, "PackedScene"):
        return null
    return ResourceLoader.load(
        room.terrain_scene_path,
        "PackedScene",
        ResourceLoader.CACHE_MODE_IGNORE
    ) as PackedScene


func _configure_preview_tree(node: Node, is_root := true) -> void:
    node.process_mode = Node.PROCESS_MODE_DISABLED
    if node is Control:
        (node as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
    if node is TileMapLayer:
        var layer := node as TileMapLayer
        layer.visible = VISIBLE_TILE_LAYERS.has(layer.name)
        layer.set("collision_enabled", false)
        layer.set("navigation_enabled", false)
    elif node is CanvasItem and not is_root and node.name != "Terrain":
        (node as CanvasItem).visible = false
    if node.has_method("set_process_input"):
        node.set_process_input(false)
    if node.has_method("set_process_unhandled_input"):
        node.set_process_unhandled_input(false)
    for child: Node in node.get_children():
        _configure_preview_tree(child, false)


func _update_room_container(room_id: String) -> void:
    if _world == null or not _room_containers.has(room_id):
        return
    var room: Resource = _world.get_room(room_id)
    var container: Control = _room_containers[room_id]
    var origin: Vector2i = _drag_origins.get(room_id, _world.get_room_origin_chunk(room_id))
    var world_origin := Vector2(origin) * CHUNK_PIXELS
    container.position = (world_origin - _view_center_world) * _view_zoom + _viewport_size * 0.5
    container.size = Vector2(room.room_size_chunks) * CHUNK_PIXELS * _view_zoom
    var instance := container.get_child(0) as Node2D
    if instance != null:
        instance.scale = Vector2.ONE * _view_zoom


func _clear_previews() -> void:
    for container: Control in _room_containers.values():
        if is_instance_valid(container):
            container.free()
    _room_containers.clear()
    _room_scene_paths.clear()
    _drag_origins.clear()
    preview_errors.clear()
