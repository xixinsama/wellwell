class_name SavePoint
extends "res://addons/platformer_kit/world/entities/world_entity.gd"

enum ActivationMode {
	CONTACT,
	INTERACT,
}

@export var activation_mode := ActivationMode.CONTACT
@export var inactive_color := Color("8aa0a8")
@export var active_color := Color("6ee7a8")

var activated := false
var _activation_consumed := false


func _ready() -> void:
	entity_type = "save_point"
	persistent = true
	var activation_area := get_node_or_null("ActivationArea") as Area2D
	if activation_area != null and not activation_area.body_entered.is_connected(_on_body_entered):
		activation_area.body_entered.connect(_on_body_entered)
	var interactable := get_node_or_null("Interactable") as Area2D
	if interactable != null and interactable.has_signal("interacted"):
		var callback := Callable(self, "_on_interacted")
		if not interactable.is_connected("interacted", callback):
			interactable.connect("interacted", callback)
		interactable.set("enabled", activation_mode == ActivationMode.INTERACT)
	_update_visual_state()


func activate(_actor: Node = null) -> bool:
	if _activation_consumed:
		return false
	var spawn := get_node_or_null("SpawnPoint") as Node2D
	if spawn == null:
		return false
	var spawn_id := String(spawn.get("spawn_id"))
	if not set_respawn_state(spawn_id, spawn.global_position):
		return false
	_activation_consumed = true
	activated = true
	commit_save_state()
	_update_visual_state()
	request_save(true)
	return true


func get_save_state() -> Dictionary:
	return {"activated": activated}


func apply_save_state(state: Dictionary) -> void:
	activated = bool(state.get("activated", false))
	_update_visual_state()


func _on_body_entered(actor: Node) -> void:
	if activation_mode == ActivationMode.CONTACT:
		activate(actor)


func _on_interacted(actor: Node) -> void:
	if activation_mode == ActivationMode.INTERACT:
		activate(actor)


func _update_visual_state() -> void:
	var visual := get_node_or_null("VisualRoot") as CanvasItem
	if visual != null:
		visual.modulate = active_color if activated else inactive_color
