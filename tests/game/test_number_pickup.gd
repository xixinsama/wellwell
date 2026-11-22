extends Node

const PICKUP_SCENE := preload("res://scenes/world/number_pickup.tscn")


func run() -> Array[String]:
	var failures: Array[String] = []
	var registry := get_node_or_null("/root/Collectibles")
	if registry == null:
		return ["Collectibles autoload is missing"]
	registry.call("reset")
	registry.set("current_world_id", "test_number_pickup")

	var pickup := PICKUP_SCENE.instantiate() as Node2D
	pickup.set("number", 7)
	add_child(pickup)
	if String(pickup.get("entity_id")) != "number_7":
		failures.append("NumberPickup did not derive its entity id from the number")
	var label := pickup.get_node_or_null("VisualRoot/Number") as Label
	if label == null or label.text != "7":
		failures.append("NumberPickup did not show its number")
	var area := pickup.get_node_or_null("ActivationArea") as Area2D
	if area == null or area.collision_layer != 0 or area.collision_mask != 2:
		failures.append("NumberPickup activation area does not detect the player layer")
	if bool(pickup.get("collected")):
		failures.append("NumberPickup started collected")
	pickup.call("collect")
	if not bool(pickup.get("collected")) or pickup.visible:
		failures.append("NumberPickup did not disappear when collected")
	if not bool(registry.call("is_collected", 7)):
		failures.append("NumberPickup did not record its number in the registry")
	if pickup.is_processing():
		failures.append("NumberPickup kept bobbing after being collected")

	var restored := PICKUP_SCENE.instantiate() as Node2D
	restored.set("number", 8)
	add_child(restored)
	restored.call("apply_save_state", {"collected": true})
	if not bool(restored.get("collected")) or restored.visible:
		failures.append("NumberPickup did not stay collected after a save restore")

	registry.call("reset")
	pickup.queue_free()
	restored.queue_free()
	return failures
