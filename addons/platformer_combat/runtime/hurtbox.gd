class_name Hurtbox
extends Area2D

const DAMAGE_EVENT := preload("res://addons/platformer_combat/runtime/damage_event.gd")

signal damage_received(event: RefCounted)

@export var team: StringName
var _health: Node
var _invulnerability: Node
var _knockback: Node


func bind_components(health: Node, invulnerability: Node = null, knockback: Node = null) -> void:
	_health = health
	_invulnerability = invulnerability
	_knockback = knockback


func receive_damage(data: Resource, source: Node = null, source_team: StringName = &"") -> bool:
	if data == null or _health == null:
		return false
	if not team.is_empty() and team == source_team:
		return false
	var event: RefCounted = DAMAGE_EVENT.create(data, source, self)
	if _invulnerability != null and _invulnerability.has_method("blocks") and _invulnerability.call("blocks", event):
		return false
	var applied := float(_health.call("apply_damage", event))
	if applied <= 0.0:
		return false
	if _knockback != null and _knockback.has_method("apply"):
		_knockback.call("apply", event)
	if _invulnerability != null and _invulnerability.has_method("begin"):
		_invulnerability.call("begin")
	damage_received.emit(event)
	return true
