@tool
class_name RoomAuthoringRoot
extends Node2D

@export var room_id := ""
@export var display_name := ""
@export var room_size_chunks := Vector2i.ONE
@export var preview_spawn_id := "default"
@export var map_color := Color.WHITE
@export var tags := PackedStringArray()


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
    return manifest


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
