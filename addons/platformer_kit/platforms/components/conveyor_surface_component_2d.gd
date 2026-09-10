class_name ConveyorSurfaceComponent2D
extends Node

@export var enabled := true
@export var surface_velocity := Vector2(48.0, 0.0)


func _ready() -> void:
    apply_surface_velocity()


func _physics_process(_delta: float) -> void:
    apply_surface_velocity()


func apply_surface_velocity() -> bool:
    var platform := get_parent() as StaticBody2D
    if platform == null:
        return false
    platform.constant_linear_velocity = surface_velocity if enabled else Vector2.ZERO
    return true


func get_surface_velocity() -> Vector2:
    return surface_velocity if enabled else Vector2.ZERO
