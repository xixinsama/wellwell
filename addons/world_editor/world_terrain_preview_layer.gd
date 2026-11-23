@tool
class_name WorldTerrainPreviewLayer
extends Control

## Read-only world terrain view.
##
## The world has one authored terrain scene (only terrain layers, in world
## cells); this layer draws that scene under the room rectangles. Worlds that do
## not have a terrain scene yet fall back to drawing each room's baked terrain
## slice, so legacy worlds keep previewing.

const CHUNK_PIXELS := Vector2(320, 180)
const VISIBLE_TILE_LAYERS: Array[String] = [
    "BackTiles", "SolidTiles", "GlassTiles", "VisionBlockTiles", "DetailTiles",
    "CrumbleTiles", "CrumbleOneWayTiles"
]

var preview_errors: Dictionary = {}
var _world: WorldData
var _room_containers: Dictionary[String, Control] = {}
var _room_scene_paths: Dictionary[String, String] = {}
var _drag_origins: Dictionary[String, Vector2i] = {}
var _view_center_world := Vector2.ZERO
var _view_zoom := 1.0
var _viewport_size := Vector2.ZERO
var _world_terrain_container: Control
var _world_terrain_stamp := ""


func _ready() -> void:
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    queue_redraw()


func _draw() -> void:
    draw_rect(Rect2(Vector2.ZERO, size), Color(0.106, 0.114, 0.129, 1.0), true)


func set_view_transform(center_world: Vector2, zoom: float, viewport_size: Vector2) -> void:
    _view_center_world = center_world
    _view_zoom = zoom
    _viewport_size = viewport_size
    for room_id: String in _room_containers:
        _update_room_container(room_id)
    _update_world_terrain_container()


func sync_world(world: WorldData) -> void:
    if _world != world:
        _clear_previews()
    _world = world
    if _world == null:
        return
    var terrain_path := String(_world.call("get_terrain_scene_path"))
    if not terrain_path.is_empty() and ResourceLoader.exists(terrain_path, "PackedScene"):
        _remove_room_containers()
        _sync_world_terrain(terrain_path)
        return
    _remove_world_terrain()
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
    if is_instance_valid(_world_terrain_container):
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


func _sync_world_terrain(terrain_path: String) -> void:
    var stamp := FileAccess.get_sha256(terrain_path)
    if is_instance_valid(_world_terrain_container) and stamp == _world_terrain_stamp:
        _update_world_terrain_container()
        return
    _remove_world_terrain()
    var scene := _load_terrain_scene_path(terrain_path)
    if scene == null:
        preview_errors["world_terrain"] = "Could not load %s" % terrain_path
        return
    var instance := scene.instantiate() as Node2D
    if instance == null:
        preview_errors["world_terrain"] = "Invalid world terrain root"
        return
    _configure_preview_tree(instance)
    var container := Control.new()
    container.name = "WorldTerrain"
    container.mouse_filter = Control.MOUSE_FILTER_IGNORE
    container.clip_contents = true
    container.z_index = 0
    add_child(container)
    container.add_child(instance)
    _world_terrain_container = container
    _world_terrain_stamp = stamp
    _update_world_terrain_container()


func _remove_world_terrain() -> void:
    if is_instance_valid(_world_terrain_container):
        _world_terrain_container.free()
    _world_terrain_container = null
    _world_terrain_stamp = ""
    preview_errors.erase("world_terrain")


## The world terrain covers the whole layer and the *instance* is moved/scaled.
##
## Clipping to a container that starts at the world origin's screen position was
## wrong: once the origin is above/left of the view, the clip rectangle ends
## inside the viewport and cuts the terrain off along a straight edge, which shows
## up as a rectangular bite that grows as you zoom in.
func _update_world_terrain_container() -> void:
    if not is_instance_valid(_world_terrain_container):
        return
    _world_terrain_container.position = Vector2.ZERO
    _world_terrain_container.size = _cover_size()
    var instance := _world_terrain_container.get_child(0) as Node2D
    if instance != null:
        instance.position = (Vector2.ZERO - _view_center_world) * _view_zoom + _viewport_size * 0.5
        instance.scale = Vector2.ONE * _view_zoom


func _remove_room_containers() -> void:
    for room_id: String in _room_containers.keys():
        remove_room(room_id)


func _refresh_room_internal(room_id: String) -> void:
    if _world == null or not _world.has_room(room_id):
        return
    var room: Resource = _world.get_room(room_id)
    var scene := _load_terrain_scene(room)
    if scene == null:
        preview_errors[room_id] = WorldEditorLocalization.t("WE_PREVIEW_TERRAIN_LOAD_FAILED", [room.terrain_scene_path])
        return
    var instance := scene.instantiate() as Node2D
    if instance == null:
        preview_errors[room_id] = WorldEditorLocalization.t("WE_PREVIEW_TERRAIN_ROOT_INVALID")
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
    return _load_terrain_scene_path(room.terrain_scene_path)


func _load_terrain_scene_path(path: String) -> PackedScene:
    if path.is_empty() or not ResourceLoader.exists(path, "PackedScene"):
        return null
    return ResourceLoader.load(path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene


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


## Same treatment as the world terrain container: the layer-sized container clips
## to the control, and the instance carries the world transform. A room's slice
## only contains that room's cells, so it needs no rectangular clip of its own —
## clipping to the room rect cut the terrain off once the room started off-screen.
func _update_room_container(room_id: String) -> void:
    if _world == null or not _room_containers.has(room_id):
        return
    var room: Resource = _world.get_room(room_id)
    var container: Control = _room_containers[room_id]
    var origin: Vector2i = _drag_origins.get(room_id, _world.get_room_origin_chunk(room_id))
    # Cell-aligned origin/size: the terrain is drawn where the room actually sits
    # on the world cell grid, and an odd row is 4 px lower (and 176 px tall).
    var cell_rect := RoomGrid.get_room_cell_rect(origin, room.room_size_chunks)
    var world_origin := Vector2(cell_rect.position * RoomGrid.DEFAULT_CELL_SIZE)
    container.position = Vector2.ZERO
    container.size = _cover_size()
    var instance := container.get_child(0) as Node2D
    if instance != null:
        instance.position = (world_origin - _view_center_world) * _view_zoom + _viewport_size * 0.5
        instance.scale = Vector2.ONE * _view_zoom


## The clip containers must cover everything the layer can show. Before the first
## layout pass `size` is still zero, so fall back to the requested viewport.
func _cover_size() -> Vector2:
    if size.x > 0.0 and size.y > 0.0:
        return size
    return _viewport_size


func _clear_previews() -> void:
    _remove_room_containers()
    _remove_world_terrain()
    preview_errors.clear()
