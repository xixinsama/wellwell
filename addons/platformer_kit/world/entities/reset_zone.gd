extends Area2D
class_name ResetZone

@export var spawn_point_path: NodePath

var spawn_point: Node2D


func _ready() -> void:
    if spawn_point_path != NodePath():
        spawn_point = get_node_or_null(spawn_point_path) as Node2D
    body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node2D) -> void:
    if spawn_point == null:
        return
    if body.has_method("respawn_at"):
        body.call("respawn_at", spawn_point.global_position)
