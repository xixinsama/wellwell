class_name OneWayPlatform
extends StaticBody2D

@export var platform_id: StringName


func _ready() -> void:
	for child: Node in get_children():
		var collision := child as CollisionShape2D
		if collision != null:
			collision.one_way_collision = true


func get_platform_velocity() -> Vector2:
	return Vector2.ZERO


func get_platform_id() -> StringName:
	return platform_id
