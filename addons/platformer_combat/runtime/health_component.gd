class_name HealthComponent
extends Node

signal health_changed(current: float, maximum: float)
signal damaged(event: RefCounted)
signal died(event: RefCounted)

@export var max_health := 1.0
var current_health := 1.0


func _ready() -> void:
	reset_to_max()


func reset_to_max() -> void:
	current_health = maxf(max_health, 0.0)
	health_changed.emit(current_health, max_health)


func apply_damage(event: RefCounted) -> float:
	if event == null or event.get("data") == null or current_health <= 0.0:
		return 0.0
	var amount := maxf(0.0, float(event.get("data").get("amount")))
	var applied := minf(amount, current_health)
	if applied <= 0.0:
		return 0.0
	current_health -= applied
	damaged.emit(event)
	health_changed.emit(current_health, max_health)
	if current_health <= 0.0:
		died.emit(event)
	return applied


func heal(amount: float) -> float:
	var previous := current_health
	current_health = minf(max_health, current_health + maxf(amount, 0.0))
	if current_health != previous:
		health_changed.emit(current_health, max_health)
	return current_health - previous


func is_dead() -> bool:
	return current_health <= 0.0
