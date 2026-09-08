@tool
class_name RoomData
extends Resource

@export var room_id := ""
@export var display_name := ""
@export_file("*.tscn") var scene_path := ""
@export_file("*.tscn") var source_scene_path := ""
@export var source_fingerprint := ""
@export_file("*.tscn") var terrain_scene_path := ""
@export var entrance_ids := PackedStringArray()
@export var spawn_ids := PackedStringArray()
@export var entity_ids := PackedStringArray()
@export var tags := PackedStringArray()
@export var room_size_chunks := Vector2i.ONE
@export var map_color := Color.WHITE
