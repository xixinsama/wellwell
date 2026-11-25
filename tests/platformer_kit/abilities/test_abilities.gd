extends Node

## Merged test suite. Every inner class below is one original test file,
## kept in its own class so fixtures and helper names stay isolated. Do not
## add logic here: split a class back into its own file when it grows.

## tests/platformer_kit/abilities/test_ability_combat_contract.gd
class AbilityCombatContractCase extends Node:
	## The ability and combat modules ship inside Platformer Kit, so they must exist
	## there and the base movement lab must stay free of them.

	const ABILITY_RUNTIME := "res://addons/platformer_kit/abilities/runtime/ability_runtime.gd"
	const ABILITY_CONTROLLER := "res://addons/platformer_kit/abilities/runtime/ability_controller.gd"
	const COMBAT_HEALTH := "res://addons/platformer_kit/combat/health_component.gd"
	const COMBAT_HITBOX := "res://addons/platformer_kit/combat/hitbox.gd"
	const ABILITY_LAB := "res://examples/ability_lab/ability_lab.tscn"
	const COMBAT_LAB := "res://examples/combat_lab/combat_lab.tscn"
	const MOVEMENT_LAB := "res://examples/movement_lab/movement_lab.tscn"


	func run() -> Array[String]:
		var failures: Array[String] = []
		for path: String in [ABILITY_RUNTIME, ABILITY_CONTROLLER, COMBAT_HEALTH, COMBAT_HITBOX]:
			if not FileAccess.file_exists(path):
				failures.append("merged kit module script is missing: %s" % path)
		for path: String in [ABILITY_LAB, COMBAT_LAB]:
			if load(path) as PackedScene == null:
				failures.append("module lab is missing: %s" % path)
		var movement_source := FileAccess.get_file_as_string(MOVEMENT_LAB)
		if movement_source.contains("platformer_kit/abilities/") or movement_source.contains("platformer_kit/combat/"):
			failures.append("base movement lab depends on an optional kit module")
		return failures


## tests/platformer_kit/abilities/test_ability_runtime.gd
class AbilityRuntimeCase extends Node:
	const DEFINITION_PATH := "res://addons/platformer_kit/abilities/runtime/ability_definition.gd"
	const CONTEXT_PATH := "res://addons/platformer_kit/abilities/runtime/ability_context.gd"
	const RUNTIME_PATH := "res://addons/platformer_kit/abilities/runtime/ability_runtime.gd"
	const CONTROLLER_PATH := "res://addons/platformer_kit/abilities/runtime/ability_controller.gd"
	const INCOMPLETE_RUNTIME_PATH := "res://tests/platformer_kit/abilities/incomplete_ability_runtime.gd"


	func run() -> Array[String]:
		var failures: Array[String] = []
		var definition_script := load(DEFINITION_PATH) as Script
		var context_script := load(CONTEXT_PATH) as Script
		var runtime_script := load(RUNTIME_PATH) as Script
		var controller_script := load(CONTROLLER_PATH) as Script
		if definition_script == null or context_script == null or runtime_script == null or controller_script == null:
			failures.append("ability runtime scripts are missing")
			return failures

		var definition: Resource = definition_script.new()
		definition.set("ability_id", &"dash")
		definition.set("cooldown_seconds", 0.5)
		definition.set("required_tags", Array([&"grounded"], TYPE_STRING_NAME, &"", null))
		var context: RefCounted = context_script.new()
		context.call("add_tag", &"grounded")
		var runtime: RefCounted = runtime_script.new()
		runtime.call("configure", definition)
		if not runtime.call("can_activate", context):
			failures.append("eligible ability could not activate")
		if not runtime.call("activate", context) or not runtime.get("active"):
			failures.append("ability activation did not enter active state")
		if not runtime.call("cancel") or runtime.get("active"):
			failures.append("ability cancellation did not leave active state")
		if not is_equal_approx(float(runtime.get("cooldown_remaining")), 0.5):
			failures.append("ability activation did not start its cooldown")
		if runtime.call("can_activate", context):
			failures.append("ability ignored its active cooldown")
		runtime.call("tick", 0.5)
		if not runtime.call("can_activate", context):
			failures.append("ability did not become eligible after cooldown")

		var missing_tag_context: RefCounted = context_script.new()
		if runtime.call("can_activate", missing_tag_context):
			failures.append("ability ignored required context tags")

		var controller: Node = controller_script.new()
		if not controller.call("add_definition", definition):
			failures.append("ability controller rejected a valid definition")
		if controller.call("get_runtime", &"dash") == null:
			failures.append("ability controller did not create runtime state")
		var invalid_definition: Resource = definition_script.new()
		invalid_definition.set("ability_id", &"invalid")
		invalid_definition.set("runtime_script", load(INCOMPLETE_RUNTIME_PATH))
		if controller.call("add_definition", invalid_definition):
			failures.append("ability controller accepted an incomplete runtime contract")
		controller.free()
		return failures


## tests/platformer_kit/abilities/test_climb_ability.gd
class ClimbAbilityCase extends Node:
	const DEFINITION_PATH := "res://addons/platformer_kit/abilities/climb/climb_ability_definition.gd"
	const DEFAULT_CLIMB_PATH := "res://addons/platformer_kit/abilities/climb/default_climb.tres"
	const LOADOUT_PATH := "res://game/player/player_ability_loadout.gd"
	const CONTROLLER_PATH := "res://addons/platformer_kit/abilities/runtime/ability_controller.gd"
	const PLAYER_SCENE_PATH := "res://scenes/player/player.tscn"
	const PICKUP_PATH := "res://addons/platformer_kit/abilities/entities/climb_pickup.tscn"
	const PROGRESSION := preload("res://addons/metroidvania_kit/progression/progression_context.gd")


	func run() -> Array[String]:
		var failures: Array[String] = []
		if not ResourceLoader.exists(DEFAULT_CLIMB_PATH):
			return ["default Climb ability resource is missing"]
		var definition: Resource = load(DEFAULT_CLIMB_PATH)
		if definition == null or StringName(definition.get("ability_id")) != &"climb":
			failures.append("default Climb ability does not use the climb id")
		_assert_loadout_grant(failures)
		_assert_player_scene_composition(failures)
		_assert_pickup_preset(failures)
		return failures


	func _assert_pickup_preset(failures: Array[String]) -> void:
		var packed := load(PICKUP_PATH) as PackedScene
		if packed == null:
			failures.append("Climb pickup preset is missing")
			return
		var pickup := packed.instantiate()
		var definition: Resource = pickup.get("ability_definition")
		if definition == null or StringName(definition.get("ability_id")) != &"climb":
			failures.append("Climb pickup preset does not carry the climb definition")
		pickup.free()


	func _assert_loadout_grant(failures: Array[String]) -> void:
		var loadout: Node = (load(LOADOUT_PATH) as Script).new()
		loadout.name = "AbilityLoadout"
		var controller: Node = (load(CONTROLLER_PATH) as Script).new()
		controller.name = "AbilityController"
		loadout.add_child(controller)
		add_child(loadout)
		var definitions: Array[Resource] = [load(DEFAULT_CLIMB_PATH)]
		loadout.set("ability_definitions", definitions)
		if not bool(loadout.call("grant_ability_definition", load(DEFAULT_CLIMB_PATH))):
			failures.append("Climb ability could not be granted through the player loadout")
		if not bool(loadout.call("has_ability", &"climb")):
			failures.append("player loadout did not expose the granted Climb ability")
		if controller.call("get_runtime", &"climb") == null:
			failures.append("Climb ability did not install a runtime entry")
		var progression: RefCounted = PROGRESSION.new()
		loadout.call("bind_progression", progression)
		if bool(loadout.call("has_ability", &"climb")):
			failures.append("empty progression did not lock Climb")
		progression.call("grant_ability", &"climb")
		loadout.call("synchronize_unlocked_abilities")
		if not bool(loadout.call("has_ability", &"climb")):
			failures.append("restored progression did not unlock Climb")
		loadout.free()


	func _assert_player_scene_composition(failures: Array[String]) -> void:
		var player := (load(PLAYER_SCENE_PATH) as PackedScene).instantiate() as CharacterBody2D
		var loadout := player.get_node_or_null("AbilityLoadout")
		if loadout == null:
			failures.append("player scene has no AbilityLoadout for Climb")
			player.free()
			return
		var definitions: Array = loadout.get("ability_definitions")
		var found := false
		for definition: Resource in definitions:
			if definition != null and StringName(definition.get("ability_id")) == &"climb":
				found = true
		if not found:
			failures.append("player scene does not author the Climb ability")
		player.free()


## tests/platformer_kit/abilities/test_ability_pickup.gd
class AbilityPickupCase extends Node:
	const PICKUP_SCENE := "res://addons/platformer_kit/abilities/entities/ability_pickup.tscn"
	const ABILITY_DEFINITION := preload("res://addons/platformer_kit/abilities/runtime/ability_definition.gd")
	const SAVE_SNAPSHOT := preload("res://addons/platformer_kit/save/save_snapshot.gd")


	class AbilityReceiver extends Node:
		var accepted := true
		var definitions: Array[Resource] = []

		func grant_ability_definition(definition: Resource) -> bool:
			if not accepted:
				return false
			if not definitions.has(definition):
				definitions.append(definition)
			return true


	func run() -> Array[String]:
		var failures: Array[String] = []
		if not ResourceLoader.exists(PICKUP_SCENE, "PackedScene"):
			return ["reusable AbilityPickup scene is missing"]
		_assert_invalid_collection_keeps_pickup(failures)
		_assert_successful_collection_persists(failures)
		_assert_duplicate_confirmation_and_restore(failures)
		_assert_contact_collection(failures)
		return failures


	func _assert_invalid_collection_keeps_pickup(failures: Array[String]) -> void:
		var pickup := _make_pickup(null)
		var receiver := AbilityReceiver.new()
		if pickup.collect_for(receiver) or pickup.collected or not pickup.visible:
			failures.append("AbilityPickup collected without a definition")
		pickup.ability_definition = _make_definition()
		var incompatible := Node.new()
		if pickup.collect_for(incompatible) or pickup.collected:
			failures.append("AbilityPickup collected for an incompatible body")
		incompatible.free()
		receiver.accepted = false
		if pickup.collect_for(receiver) or pickup.collected:
			failures.append("AbilityPickup collected after the receiver rejected the grant")
		pickup.free()
		receiver.free()


	func _assert_successful_collection_persists(failures: Array[String]) -> void:
		var definition := _make_definition()
		var snapshot: RefCounted = SAVE_SNAPSHOT.new()
		var pickup := _make_pickup(definition, snapshot)
		var receiver := AbilityReceiver.new()
		var requests: Array[bool] = []
		pickup.save_requested.connect(func(immediate: bool) -> void: requests.append(immediate))
		if not pickup.collect_for(receiver):
			failures.append("AbilityPickup rejected a compatible receiver")
		if receiver.definitions != [definition]:
			failures.append("AbilityPickup did not grant its configured definition")
		if not pickup.collected or pickup.visible:
			failures.append("AbilityPickup did not hide after collection")
		if not bool(snapshot.get_entity_state("world_a:room_a:ability_pickup").get("collected", false)):
			failures.append("AbilityPickup did not persist collection state")
		if requests != [true]:
			failures.append("AbilityPickup did not request one immediate save")
		pickup.free()
		receiver.free()


	func _assert_duplicate_confirmation_and_restore(failures: Array[String]) -> void:
		var definition := _make_definition()
		var receiver := AbilityReceiver.new()
		receiver.definitions.append(definition)
		var pickup := _make_pickup(definition)
		if not pickup.collect_for(receiver) or not pickup.collected:
			failures.append("AbilityPickup did not accept confirmed duplicate ownership")
		pickup.free()
		receiver.free()

		var restored := _make_pickup(definition)
		restored.apply_save_state({"collected": true})
		if not restored.collected or restored.visible:
			failures.append("AbilityPickup did not restore its persistent hidden state")
		restored.free()


	func _assert_contact_collection(failures: Array[String]) -> void:
		var pickup := _make_pickup(_make_definition())
		var receiver := AbilityReceiver.new()
		var activation_area := pickup.get_node("ActivationArea") as Area2D
		if activation_area.collision_layer != 0 or activation_area.collision_mask != 2:
			failures.append("AbilityPickup contact area does not detect the player collision layer")
		activation_area.emit_signal("body_entered", receiver)
		if not pickup.collected:
			failures.append("AbilityPickup did not collect on body entry")
		pickup.free()
		receiver.free()


	func _make_pickup(definition: Resource, snapshot: RefCounted = null) -> Node:
		var pickup := (load(PICKUP_SCENE) as PackedScene).instantiate()
		pickup.ability_definition = definition
		pickup.entity_id = "ability_pickup"
		pickup.setup_entity({
			"world_id": "world_a",
			"room_id": "room_a",
			"entity_state_sink": snapshot if snapshot != null else SAVE_SNAPSHOT.new(),
		})
		add_child(pickup)
		return pickup


	func _make_definition() -> Resource:
		var definition: Resource = ABILITY_DEFINITION.new()
		definition.ability_id = &"dash"
		return definition


func run() -> Array[String]:
	var failures: Array[String] = []
	failures.append_array(_run_case(AbilityCombatContractCase.new()))
	failures.append_array(_run_case(AbilityRuntimeCase.new()))
	failures.append_array(_run_case(ClimbAbilityCase.new()))
	failures.append_array(_run_case(AbilityPickupCase.new()))
	return failures


func _run_case(test: Node) -> Array[String]:
	add_child(test)
	var result: Array = test.call("run")
	test.queue_free()
	var failures: Array[String] = []
	failures.assign(result)
	return failures
