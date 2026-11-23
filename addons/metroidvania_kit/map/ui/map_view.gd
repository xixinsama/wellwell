class_name MapView
extends Control

@export_range(0.25, 4.0, 0.05) var zoom := 1.0:
    set(value):
        zoom = clampf(value, 0.25, 4.0)
        if is_node_ready():
            $Renderer.scale = Vector2.ONE * zoom

var runtime: RefCounted


func _ready() -> void:
    $Renderer.scale = Vector2.ONE * zoom


func bind_runtime(value: RefCounted) -> void:
    runtime = value
    $Renderer.bind_runtime(value)


func focus_room(room_id: StringName) -> bool:
    if runtime == null:
        return false
    var room: Resource = runtime.call("get_map_room", room_id)
    if room == null:
        return false
    var room_scale: Vector2 = $Renderer.room_scale
    $Renderer.position = size * 0.5 - Vector2(Vector2i(room.get("map_position"))) * room_scale * zoom
    return true
