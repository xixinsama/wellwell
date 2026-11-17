class_name DashAbilityRuntime
extends "res://addons/platformer_abilities/runtime/ability_runtime.gd"

var _velocity_override := Vector2.ZERO
var _dash_direction := Vector2.ZERO
var _remaining_duration := 0.0
var _charges := 0


func configure(value: Resource) -> void:
    super.configure(value)
    _charges = get_max_charges()


## Dashes left before a refill. Unlimited dashes report 0 here as well; use
## has_unlimited_charges() to tell the two apart.
func get_charges() -> int:
    return _charges


func get_max_charges() -> int:
    if definition == null:
        return 0
    return maxi(0, int(definition.get("max_charges")))


func has_unlimited_charges() -> bool:
    return get_max_charges() == 0


## Restores the dash count, like landing or surfacing for air.
func refill() -> void:
    _charges = get_max_charges()


func get_velocity_override() -> Vector2:
    return _velocity_override if active else Vector2.ZERO


## The normalized dash direction (one of the eight compass directions when the
## definition snaps to 45 degrees). Zero while the dash is inactive.
func get_dash_direction() -> Vector2:
    return _dash_direction if active else Vector2.ZERO


func is_motion_overriding() -> bool:
    return active


func _can_activate(_context: RefCounted) -> bool:
    return has_unlimited_charges() or _charges > 0


func _on_activate(context: RefCounted) -> void:
    if not has_unlimited_charges():
        _charges = maxi(0, _charges - 1)
    _dash_direction = _resolve_direction(context)
    _velocity_override = _dash_direction * maxf(0.0, float(definition.get("dash_speed")))
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
    var data: Dictionary = context.get("data")
    var raw := Vector2(data.get("direction", Vector2.ZERO))
    if not bool(definition.get("eight_directional")):
        raw.y = 0.0
    var deadzone := clampf(float(definition.get("direction_deadzone")), 0.0, 1.0)
    if raw.length() <= deadzone:
        var facing := signf(float(data.get("facing", 1)))
        raw = Vector2(-1.0 if is_zero_approx(facing) else facing, 0.0)
    var snap := float(definition.get("direction_snap_degrees"))
    if snap > 0.0 and snap < 360.0:
        var step := deg_to_rad(snap)
        raw = Vector2.from_angle(roundf(raw.angle() / step) * step)
        # Vector2 is 32-bit: cos(PI/2) is not exactly zero. Clean the residual
        # so a straight dash is exactly axis-aligned.
        if absf(raw.x) < 0.001:
            raw.x = 0.0
        if absf(raw.y) < 0.001:
            raw.y = 0.0
    return raw.normalized()


func _clear_motion() -> void:
    _velocity_override = Vector2.ZERO
    _dash_direction = Vector2.ZERO
    _remaining_duration = 0.0
