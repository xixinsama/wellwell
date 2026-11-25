extends Node

## Merged test suite. Every inner class below is one original test file,
## kept in its own class so fixtures and helper names stay isolated. Do not
## add logic here: split a class back into its own file when it grows.

## tests/game/test_number_pickup.gd
class NumberPickupCase extends Node:
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


## tests/game/test_player_interaction.gd
class PlayerInteractionCase extends Node:
	const DETECTOR := preload("res://addons/platformer_kit/interaction/interaction_detector.gd")
	const INTERACTABLE := preload("res://addons/platformer_kit/interaction/interactable.gd")
	const CONTROLLER := preload("res://game/interaction/player_interaction_controller.gd")


	class FakeActor extends CharacterBody2D:
		var control_locked := false


	func run() -> Array[String]:
		var failures: Array[String] = []
		_assert_interact_uses_the_candidate(failures)
		_assert_locked_actor_ignores_presses(failures)
		_assert_paused_tree_ignores_presses(failures)
		return failures


	func _make_rig() -> Dictionary:
		var actor := FakeActor.new()
		var detector := Area2D.new()
		detector.name = "InteractionDetector"
		detector.set_script(DETECTOR)
		detector.collision_layer = 0
		detector.collision_mask = 4
		actor.add_child(detector)
		var controller := Node.new()
		controller.name = "InteractionController"
		controller.set_script(CONTROLLER)
		actor.add_child(controller)
		add_child(actor)
		var target := INTERACTABLE.new() as Area2D
		target.name = "Target"
		target.position = Vector2(8.0, 0.0)
		add_child(target)
		return {"actor": actor, "detector": detector, "controller": controller, "target": target}


	func _register(rig: Dictionary) -> Array[Node]:
		var hits: Array[Node] = []
		(rig["target"] as Node).connect(
			&"interacted", func(actor: Node) -> void: hits.append(actor)
		)
		(rig["detector"] as Node).call("register_candidate", rig["target"])
		return hits


	func _assert_interact_uses_the_candidate(failures: Array[String]) -> void:
		var rig := _make_rig()
		var hits := _register(rig)
		var controller := rig["controller"] as Node
		if not bool(controller.call("try_interact")):
			failures.append("interaction controller refused a registered candidate")
		if hits.size() != 1 or hits[0] != rig["actor"]:
			failures.append("interaction controller did not pass its actor to the interactable")
		if controller.call("get_candidate") != rig["target"]:
			failures.append("interaction controller did not expose the selected candidate")
		(rig["target"] as Node).free()
		(rig["actor"] as Node).free()


	func _assert_locked_actor_ignores_presses(failures: Array[String]) -> void:
		var rig := _make_rig()
		var hits := _register(rig)
		(rig["actor"] as Node).set("control_locked", true)
		var controller := rig["controller"] as Node
		if bool(controller.call("try_interact")):
			failures.append("a control-locked actor still interacted")
		if controller.call("get_candidate") != null or not hits.is_empty():
			failures.append("a control-locked actor still selected a candidate")
		(rig["target"] as Node).free()
		(rig["actor"] as Node).free()


	func _assert_paused_tree_ignores_presses(failures: Array[String]) -> void:
		var rig := _make_rig()
		var hits := _register(rig)
		get_tree().paused = true
		var controller := rig["controller"] as Node
		if bool(controller.call("try_interact")) or not hits.is_empty():
			failures.append("interaction controller interacted while the tree was paused")
		get_tree().paused = false
		(rig["target"] as Node).free()
		(rig["actor"] as Node).free()


## tests/game/test_collectibles.gd
class CollectiblesCase extends Node:
	const SNAPSHOT := preload("res://addons/platformer_kit/save/save_snapshot.gd")
	const ROOM_DATA := preload("res://addons/platformer_kit/world/data/room_data.gd")
	const WORLD_DATA := preload("res://addons/platformer_kit/world/data/world_data.gd")
	const PICKUP_SCENE := preload("res://scenes/world/number_pickup.tscn")
	const SCAN_SCENE_PATH := "user://test_collectible_scan_room.tscn"


	func run() -> Array[String]:
		var failures: Array[String] = []
		var registry := get_node_or_null("/root/Collectibles")
		if registry == null:
			return ["Collectibles autoload is missing"]
		registry.call("reset")
		registry.set("current_world_id", "world_a")
		registry.call("register_number", 1)
		registry.call("register_number", 3)
		registry.call("register_number", 5)
		registry.call("collect_number", 3)
		if registry.call("get_known_numbers") != ([1, 3, 5] as Array[int]):
			failures.append("known numbers are wrong: %s" % str(registry.call("get_known_numbers")))
		if int(registry.call("get_total")) != 3 or int(registry.call("get_collected_count")) != 1:
			failures.append("collection totals are wrong")

		# Each world keeps its own numbering.
		registry.call("register_number", 1, "world_b")
		registry.call("collect_number", 2, "world_b")
		if bool(registry.call("is_collected", 3, "world_b")):
			failures.append("world B inherited world A's collection")
		if not bool(registry.call("is_collected", 2, "world_b")):
			failures.append("world B did not store its own number")
		if registry.call("get_known_numbers", "world_b") != ([1, 2] as Array[int]):
			failures.append("world B numbers are wrong: %s" % str(registry.call("get_known_numbers", "world_b")))

		# Round trip through the save snapshot.
		var snapshot: RefCounted = SNAPSHOT.new()
		registry.call("write_to_snapshot", snapshot)
		registry.call("reset")
		if int(registry.call("get_total")) != 0:
			failures.append("reset did not clear the registry")
		registry.call("load_from_snapshot", snapshot)
		if not bool(registry.call("is_collected", 3, "world_a")):
			failures.append("collected numbers did not survive the snapshot")
		if not bool(registry.call("is_collected", 2, "world_b")):
			failures.append("world B's numbers did not survive the snapshot")
		if bool(registry.call("is_collected", 1, "world_a")):
			failures.append("an uncollected number came back collected")

		# Known numbers come back from the scan, not from the save.
		registry.set("current_world_id", "world_a")
		registry.call("register_number", 1)
		registry.call("register_number", 3)
		registry.call("register_number", 5)
		if int(registry.call("get_total")) != 3 or int(registry.call("get_collected_count")) != 1:
			failures.append("rescanning after a load did not restore the totals")
		_assert_scan_discovers_pickups(registry, failures)
		registry.call("reset")
		return failures


	## The full set is discovered from the baked rooms, so the screen knows every
	## number without extra authoring.
	func _assert_scan_discovers_pickups(registry: Node, failures: Array[String]) -> void:
		registry.call("reset")
		var packed := PackedScene.new()
		var root := Node2D.new()
		var pickup := PICKUP_SCENE.instantiate() as Node2D
		pickup.set("number", 4)
		root.add_child(pickup)
		pickup.owner = root
		if packed.pack(root) != OK:
			failures.append("could not pack the scan fixture")
			root.free()
			return
		root.free()
		if ResourceSaver.save(packed, SCAN_SCENE_PATH) != OK:
			failures.append("could not save the scan fixture")
			return
		var room: Resource = ROOM_DATA.new()
		room.set("room_id", "scan_room")
		room.set("scene_path", SCAN_SCENE_PATH)
		var world: Resource = WORLD_DATA.new()
		world.set("world_id", "scan_world")
		world.get("rooms").append(room)
		registry.call("scan_world", world)
		var numbers: Array = registry.call("get_known_numbers")
		if numbers != [4]:
			failures.append("scan_world did not discover the pickup number: %s" % str(numbers))
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SCAN_SCENE_PATH))


func run() -> Array[String]:
	var failures: Array[String] = []
	failures.append_array(_run_case(NumberPickupCase.new()))
	failures.append_array(_run_case(PlayerInteractionCase.new()))
	failures.append_array(_run_case(CollectiblesCase.new()))
	return failures


func _run_case(test: Node) -> Array[String]:
	add_child(test)
	var result: Array = test.call("run")
	test.queue_free()
	var failures: Array[String] = []
	failures.assign(result)
	return failures
