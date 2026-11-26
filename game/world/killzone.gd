class_name Killzone
extends Area2D


func _ready() -> void:
	add_to_group(&"hazard_zone")
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node2D) -> void:
	if not body.is_in_group("player") or not body.has_method("respawn_at"):
		return
	var target: Variant = body.get("spawn_position")
	if not target is Vector2:
		return
	body.call("respawn_at", target)
	if body.has_method("play_hurt_effect"):
		body.call("play_hurt_effect")
