class_name RiderTriggerComponent2D
extends Area2D

signal rider_triggered(rider: CharacterBody2D)

@export var target_paths: Array[NodePath] = []
@export var required_group := StringName()
@export var trigger_once := true

var _triggered := false


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func trigger_body(body: Node) -> bool:
	var rider := body as CharacterBody2D
	if rider == null or (_triggered and trigger_once):
		return false
	if not required_group.is_empty() and not rider.is_in_group(required_group):
		return false
	var activated_any := false
	for path: NodePath in target_paths:
		var target := get_node_or_null(path)
		if target != null and target.has_method("activate"):
			target.call("activate")
			activated_any = true
	if not activated_any:
		return false
	_triggered = true
	rider_triggered.emit(rider)
	return true


func reset_component() -> void:
	_triggered = false


func _on_body_entered(body: Node) -> void:
	trigger_body(body)
