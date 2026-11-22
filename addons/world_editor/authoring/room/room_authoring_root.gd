@tool
class_name RoomAuthoringRoot
extends Node2D

const ROOM_BAKE_PATHS: Script = preload("res://addons/world_editor/authoring/room/room_bake_paths.gd")

@export var room_id := ""
@export var display_name := ""
@export var room_size_chunks := Vector2i.ONE:
    set(value):
        room_size_chunks = value
        _refresh_cell_frame()
@export var preview_spawn_id := "default"
@export var map_color := Color.WHITE
@export var tags := PackedStringArray()

@export_group("World Placement")
## Chunk the room is placed at in its world. The world editor writes this when it
## opens or imports the room, so the cell frame in the room scene knows the
## room's parity (a chunk row is 23 or 22 cells).
@export var world_origin_chunk := Vector2i.ZERO:
    set(value):
        world_origin_chunk = value
        _refresh_cell_frame()
## True once the world editor has written [member world_origin_chunk]. A scene
## that was never opened from a world shows the frame in its "not synced" colour.
@export var world_origin_known := false:
    set(value):
        world_origin_known = value
        _refresh_cell_frame()

var _cell_frame: RoomCellFrame


func _ready() -> void:
    if Engine.is_editor_hint():
        _ensure_cell_frame()
        _ensure_terrain_slice()


## Per-block cell rectangles in room-local cells, e.g. a 2x2 room returns four
## rectangles whose heights alternate 23 / 22 according to the world origin.
func get_room_block_cell_rects() -> Array[Rect2i]:
    return RoomGrid.get_room_block_cell_rects(world_origin_chunk, room_size_chunks)


## The frame is an internal child, so it is never written into the saved scene;
## it is recreated whenever the scene is opened in the editor.
func _ensure_cell_frame() -> void:
    if is_instance_valid(_cell_frame):
        _cell_frame.queue_redraw()
        return
    _cell_frame = RoomCellFrame.new()
    _cell_frame.name = "RoomCellFrame"
    add_child(_cell_frame, false, Node.INTERNAL_MODE_FRONT)


func _refresh_cell_frame() -> void:
    if is_instance_valid(_cell_frame):
        _cell_frame.queue_redraw()


## Shows the room's baked world-terrain slice inside the room scene, so a room
## and the world view agree on the terrain. The preview node has no owner, so it
## is never written into the saved scene; it is recreated when the scene opens.
func _ensure_terrain_slice() -> void:
    if room_id.is_empty():
        return
    var paths: Dictionary = ROOM_BAKE_PATHS.for_room_id(room_id)
    var path := String(paths.get("terrain_scene_path", ""))
    if path.is_empty() or not ResourceLoader.exists(path, "PackedScene"):
        return
    var packed := ResourceLoader.load(path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
    if packed == null:
        return
    var baked := packed.instantiate() as Node2D
    if baked == null:
        return
    var terrain := baked.get_node_or_null("Terrain")
    if terrain == null:
        baked.free()
        return
    baked.remove_child(terrain)
    baked.free()
    terrain.name = "WorldTerrainSlice"
    terrain.process_mode = Node.PROCESS_MODE_DISABLED
    _clear_owners(terrain)
    var tile_layers: Array[TileMapLayer] = []
    _collect_tile_layers(terrain, tile_layers)
    for layer: TileMapLayer in tile_layers:
        layer.set("collision_enabled", false)
        layer.set("navigation_enabled", false)
    var room_content := get_room_content()
    if room_content == null:
        terrain.free()
        return
    room_content.add_child(terrain)
    var background := room_content.get_node_or_null("Background")
    if background != null:
        room_content.move_child(terrain, background.get_index() + 1)


func _clear_owners(node: Node) -> void:
    node.owner = null
    for child: Node in node.get_children():
        _clear_owners(child)


func _collect_tile_layers(node: Node, layers: Array[TileMapLayer]) -> void:
    if node is TileMapLayer:
        layers.append(node as TileMapLayer)
    for child: Node in node.get_children():
        _collect_tile_layers(child, layers)


func get_room_content() -> Node:
    return get_node_or_null("RoomContent")


func get_preview_root() -> Node:
    return get_node_or_null("PreviewOnly")


func isolates_preview_persistence() -> bool:
    return true


func get_manifest() -> Dictionary:
    var manifest: Dictionary = {
        "room_id": room_id,
        "display_name": display_name,
        "room_size_chunks": room_size_chunks,
        "preview_spawn_id": preview_spawn_id,
        "map_color": map_color,
        "tags": tags.duplicate(),
        "entrance_ids": [],
        "spawn_ids": [],
        "persistent_entity_ids": [],
    }
    var entrance_ids: Array[String] = []
    var spawn_ids: Array[String] = []
    var persistent_entity_ids: Array[String] = []
    var room_content: Node = get_room_content()
    if room_content != null:
        _collect_manifest_ids(room_content, entrance_ids, spawn_ids, persistent_entity_ids)
    entrance_ids.sort()
    spawn_ids.sort()
    persistent_entity_ids.sort()
    manifest["entrance_ids"] = entrance_ids
    manifest["spawn_ids"] = spawn_ids
    manifest["persistent_entity_ids"] = persistent_entity_ids
    manifest["preview_spawn_id"] = _resolved_preview_spawn_id(spawn_ids)
    return manifest


## SpawnPoint IDs in RoomContent, de-duplicated and sorted. The preview spawn is
## resolved from this list so a renamed spawn cannot strand it.
func get_spawn_ids() -> Array[String]:
    var spawn_ids: Array[String] = []
    var room_content: Node = get_room_content()
    if room_content != null:
        _collect_spawn_ids(room_content, spawn_ids)
    spawn_ids.sort()
    return spawn_ids


## The preview spawn to use: the authored ID while it still exists, otherwise the
## first spawn in the room. A new room therefore only needs its spawn point.
func resolve_preview_spawn_id() -> String:
    return _resolved_preview_spawn_id(get_spawn_ids())


## Keeps the preview spawn in sync when its SpawnPoint is renamed. Renaming any
## other spawn only matters when the authored preview ID no longer exists.
func on_spawn_id_renamed(previous_id: String, new_id: String) -> void:
    if previous_id.is_empty() or new_id.is_empty() or previous_id == new_id:
        return
    if preview_spawn_id == previous_id or not get_spawn_ids().has(preview_spawn_id):
        preview_spawn_id = new_id


func _resolved_preview_spawn_id(spawn_ids: Array[String]) -> String:
    if spawn_ids.is_empty():
        return ""
    if spawn_ids.has(preview_spawn_id):
        return preview_spawn_id
    return spawn_ids[0]


func _collect_spawn_ids(node: Node, spawn_ids: Array[String]) -> void:
    if node is SpawnPoint:
        var spawn: SpawnPoint = node as SpawnPoint
        if not spawn.spawn_id.is_empty() and not spawn_ids.has(spawn.spawn_id):
            spawn_ids.append(spawn.spawn_id)
    for child: Node in node.get_children():
        _collect_spawn_ids(child, spawn_ids)


func _collect_manifest_ids(node: Node, entrance_ids: Array[String], spawn_ids: Array[String], persistent_entity_ids: Array[String]) -> void:
    if node is RoomEntrance:
        var entrance: RoomEntrance = node as RoomEntrance
        if not entrance.entity_id.is_empty():
            entrance_ids.append(entrance.entity_id)
    if node is SpawnPoint:
        var spawn: SpawnPoint = node as SpawnPoint
        if not spawn.spawn_id.is_empty():
            spawn_ids.append(spawn.spawn_id)
    if node is WorldEntity:
        var entity: WorldEntity = node as WorldEntity
        if entity.persistent and not entity.entity_id.is_empty():
            persistent_entity_ids.append(entity.entity_id)
    for child: Node in node.get_children():
        _collect_manifest_ids(child, entrance_ids, spawn_ids, persistent_entity_ids)
