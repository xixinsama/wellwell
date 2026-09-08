class_name ConveyorPlatform
extends StaticBody2D

@export var platform_id: StringName
@export var conveyor_velocity := Vector2(48.0, 0.0)


func _ready() -> void:
	constant_linear_velocity = conveyor_velocity


func _physics_process(_delta: float) -> void:
	constant_linear_velocity = conveyor_velocity


func get_platform_velocity() -> Vector2:
	return conveyor_velocity


func get_platform_id() -> StringName:
	return platform_id
