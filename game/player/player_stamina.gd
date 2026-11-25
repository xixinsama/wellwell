class_name PlayerStamina
extends Node

signal changed(current: float, maximum: float, tired: bool)

var _current := 110.0
var _maximum := 110.0
var _tired_threshold := 20.0


func _ready() -> void:
	_current = _maximum


func configure(profile: Resource) -> void:
	if profile == null:
		return
	_maximum = maxf(0.0, float(profile.get("max_stamina")))
	_tired_threshold = maxf(0.0, float(profile.get("stamina_tired_threshold")))
	_current = _maximum
	_emit_changed()


func drain(rate: float, delta: float) -> void:
	if rate <= 0.0 or delta <= 0.0:
		return
	_set_current(_current - rate * delta)


func spend(amount: float) -> bool:
	if amount <= 0.0:
		return true
	if _current + 0.0001 < amount:
		_set_current(0.0)
		return false
	_set_current(_current - amount)
	return true


func refund(amount: float) -> void:
	if amount <= 0.0:
		return
	_set_current(_current + amount)


func refill() -> void:
	_set_current(_maximum)


func is_tired() -> bool:
	return _current <= _tired_threshold


func is_empty() -> bool:
	return _current <= 0.0001


func get_current() -> float:
	return _current


func get_maximum() -> float:
	return _maximum


func _set_current(value: float) -> void:
	var next := clampf(value, 0.0, _maximum)
	if is_equal_approx(next, _current):
		return
	_current = next
	_emit_changed()


func _emit_changed() -> void:
	changed.emit(_current, _maximum, is_tired())


func reset() -> void:
	_maximum = 110.0
	_tired_threshold = 20.0
	_current = _maximum
	_emit_changed()
