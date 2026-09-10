class_name DashAbilityRuntime
extends "res://addons/platformer_abilities/runtime/ability_runtime.gd"

var _velocity_override := Vector2.ZERO
var _remaining_duration := 0.0


func get_velocity_override() -> Vector2:
    return _velocity_override if active else Vector2.ZERO


func is_motion_overriding() -> bool:
    return active


func _on_activate(context: RefCounted) -> void:
    var direction := _resolve_direction(context)
    _velocity_override = direction * maxf(0.0, float(definition.get("dash_speed")))
    _remaining_duration = maxf(0.0, float(definition.get("dash_duration")))
    if _remaining_duration <= 0.0:
        finish()


func _on_tick(delta: float) -> void:
    _remaining_duration = maxf(0.0, _remaining_duration - delta)
    if _remaining_duration <= 0.000001:
        finish()


func _on_cancel() -> void:
    _clear_motion()


func _on_finish() -> void:
    _clear_motion()


func _resolve_direction(context: RefCounted) -> Vector2:
    var direction := Vector2(context.get("data").get("direction", Vector2.ZERO))
    if direction.is_zero_approx():
        var facing := signf(float(context.get("data").get("facing", 1)))
        direction = Vector2(-1.0 if is_zero_approx(facing) else facing, 0.0)
    return direction.normalized()


func _clear_motion() -> void:
    _velocity_override = Vector2.ZERO
    _remaining_duration = 0.0
