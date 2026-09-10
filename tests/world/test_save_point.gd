extends Node

const SAVE_POINT_SCENE := "res://addons/platformer_kit/world/entities/save_point.tscn"
const SAVE_SNAPSHOT := preload("res://addons/platformer_kit/save/save_snapshot.gd")


func run() -> Array[String]:
	var failures: Array[String] = []
	if not ResourceLoader.exists(SAVE_POINT_SCENE, "PackedScene"):
		return ["reusable SavePoint scene is missing"]
	_assert_scene_contract_and_activation(failures)
	_assert_activation_modes(failures)
	_assert_restored_state_is_visual_and_reusable(failures)
	return failures


func _assert_scene_contract_and_activation(failures: Array[String]) -> void:
	var checkpoint := _make_checkpoint(0)
	if checkpoint == null:
		failures.append("SavePoint scene could not be instantiated")
		return
	for path: String in ["VisualRoot", "ActivationArea/CollisionShape2D", "Interactable/CollisionShape2D", "SpawnPoint"]:
		if checkpoint.get_node_or_null(path) == null:
			failures.append("SavePoint scene is missing %s" % path)
	var activation_area := checkpoint.get_node("ActivationArea") as Area2D
	if activation_area.collision_layer != 0 or activation_area.collision_mask != 2:
		failures.append("SavePoint contact area does not detect the player collision layer")
	var interactable := checkpoint.get_node("Interactable") as Area2D
	if interactable.collision_layer != 4 or interactable.collision_mask != 0:
		failures.append("SavePoint interactable is not exposed on the trigger layer")
	var snapshot: RefCounted = SAVE_SNAPSHOT.new()
	checkpoint.entity_id = "checkpoint_01"
	checkpoint.position = Vector2(100, 40)
	checkpoint.setup_entity({
		"world_id": "world_a",
		"room_id": "room_a",
		"entity_state_sink": snapshot,
	})
	var requests: Array[bool] = []
	checkpoint.save_requested.connect(func(immediate: bool) -> void: requests.append(immediate))
	if not checkpoint.activate():
		failures.append("SavePoint rejected its first valid activation")
	var spawn := checkpoint.get_node("SpawnPoint") as Node2D
	if snapshot.respawn_room_id != "room_a" or snapshot.respawn_spawn_id != String(spawn.get("spawn_id")):
		failures.append("SavePoint did not update the snapshot respawn identity")
	if snapshot.respawn_position != spawn.global_position:
		failures.append("SavePoint did not store the nested SpawnPoint position")
	if not bool(snapshot.get_entity_state("world_a:room_a:checkpoint_01").get("activated", false)):
		failures.append("SavePoint did not persist its activated state")
	if requests != [true]:
		failures.append("SavePoint did not request one immediate save")
	if checkpoint.activate() or requests.size() != 1:
		failures.append("SavePoint activated more than once in one room instance")
	checkpoint.free()


func _assert_activation_modes(failures: Array[String]) -> void:
	var actor := Node2D.new()
	var contact := _make_checkpoint(0)
	var contact_requests: Array[bool] = []
	contact.save_requested.connect(func(immediate: bool) -> void: contact_requests.append(immediate))
	contact.get_node("ActivationArea").emit_signal("body_entered", actor)
	if contact_requests != [true]:
		failures.append("contact-mode SavePoint ignored body entry")
	contact.free()

	var interaction := _make_checkpoint(1)
	var interaction_requests: Array[bool] = []
	interaction.save_requested.connect(func(immediate: bool) -> void: interaction_requests.append(immediate))
	interaction.get_node("ActivationArea").emit_signal("body_entered", actor)
	if not interaction_requests.is_empty():
		failures.append("interaction-mode SavePoint activated on contact")
	interaction.get_node("Interactable").call("interact", actor)
	if interaction_requests != [true]:
		failures.append("interaction-mode SavePoint ignored interaction")
	interaction.free()
	actor.free()


func _assert_restored_state_is_visual_and_reusable(failures: Array[String]) -> void:
	var checkpoint := _make_checkpoint(0)
	checkpoint.apply_save_state({"activated": true})
	if not checkpoint.activated:
		failures.append("SavePoint did not restore activated state")
	var visual := checkpoint.get_node("VisualRoot") as CanvasItem
	if visual.modulate != checkpoint.active_color:
		failures.append("SavePoint did not restore its activated visual")
	if not checkpoint.activate():
		failures.append("restored SavePoint stayed transiently locked in a new room instance")
	checkpoint.free()


func _make_checkpoint(mode: int) -> Node:
	var packed := load(SAVE_POINT_SCENE) as PackedScene
	if packed == null:
		return null
	var checkpoint := packed.instantiate()
	checkpoint.activation_mode = mode
	checkpoint.entity_id = "checkpoint_fixture"
	checkpoint.setup_entity({
		"world_id": "world_a",
		"room_id": "room_a",
		"entity_state_sink": SAVE_SNAPSHOT.new(),
	})
	add_child(checkpoint)
	return checkpoint
