extends Node

## Merged test suite. Every inner class below is one original test file,
## kept in its own class so fixtures and helper names stay isolated. Do not
## add logic here: split a class back into its own file when it grows.

## tests/world/test_world_entity.gd
class WorldEntityCase extends Node:
	const WORLD_ENTITY := preload("res://addons/platformer_kit/world/entities/world_entity.gd")
	const SWITCH_ENTITY := preload("res://addons/platformer_kit/world/entities/switch_entity.gd")
	const PICKUP_ENTITY := preload("res://addons/platformer_kit/world/entities/pickup_entity.gd")
	const ROOM_ENTRANCE := preload("res://addons/platformer_kit/world/entities/room_entrance.gd")


	class StateSink extends RefCounted:
		var states: Dictionary = {}

		func set_entity_state(key: String, state: Dictionary) -> void:
			states[key] = state.duplicate(true)

	func run() -> Array[String]:
		var failures: Array[String] = []
		var entity: Node = WORLD_ENTITY.new()
		entity.entity_id = "switch_01"
		entity.setup_entity({"world_id": "world_01", "room_id": "room_a"})
		if entity.get_save_key() != "world_01:room_a:switch_01":
			failures.append("world entity did not build a stable save key from setup context")
		entity.persistent_id = &"switch:forest:001"
		if entity.get_save_key() != "switch:forest:001":
			failures.append("world entity did not prefer its explicit persistent_id")
		if entity.get_persistent_id() != &"switch:forest:001":
			failures.append("world entity did not expose the Saveable persistent ID contract")
		entity.free()

		var switch_entity: Node = SWITCH_ENTITY.new()
		switch_entity.activated = true
		var switch_state: Dictionary = switch_entity.get_save_state()
		switch_entity.activated = false
		switch_entity.apply_save_state(switch_state)
		if not switch_entity.activated:
			failures.append("switch state did not round trip")
		switch_entity.free()

		var pickup: Node = PICKUP_ENTITY.new()
		pickup.collected = true
		var pickup_state: Dictionary = pickup.get_save_state()
		pickup.collected = false
		pickup.apply_save_state(pickup_state)
		if not pickup.collected:
			failures.append("pickup state did not round trip")
		pickup.free()

		_assert_entity_mutations_commit_to_the_state_sink(failures)
		_assert_entity_emits_save_requests(failures)

		var entrance: Node = ROOM_ENTRANCE.new()
		for property_info: Dictionary in entrance.get_property_list():
			var property_name := String(property_info.get("name", ""))
			if property_name in ["target_room_id", "target_spawn_id"]:
				failures.append("room entrance still serializes a transition target")
		entrance.free()
		return failures


	func _assert_entity_emits_save_requests(failures: Array[String]) -> void:
		var entity: Node = WORLD_ENTITY.new()
		if not entity.has_signal("save_requested") or not entity.has_method("request_save"):
			failures.append("world entities must expose generic save requests")
			entity.free()
			return
		var requests: Array[bool] = []
		entity.connect("save_requested", func(immediate: bool) -> void: requests.append(immediate))
		entity.call("request_save")
		entity.call("request_save", true)
		if requests != [false, true]:
			failures.append("world entity save requests did not preserve immediate intent")
		entity.free()


	func _assert_entity_mutations_commit_to_the_state_sink(failures: Array[String]) -> void:
		var pickup: Node = PICKUP_ENTITY.new()
		var sink := StateSink.new()
		pickup.entity_id = "pickup_01"
		pickup.persistent = true
		pickup.setup_entity({
			"world_id": "world_01",
			"room_id": "room_a",
			"entity_state_sink": sink,
		})
		if not pickup.has_method("commit_save_state"):
			failures.append("persistent entities must expose commit_save_state")
		else:
			pickup.collect()
			var state: Dictionary = sink.states.get("world_01:room_a:pickup_01", {})
			if not bool(state.get("collected", false)):
				failures.append("collecting a pickup must immediately write its state")
		pickup.free()


## tests/world/test_save_point.gd
class SavePointCase extends Node:
	const SAVE_POINT_SCENE := "res://addons/platformer_kit/world/entities/save_point.tscn"
	const SAVE_SNAPSHOT := preload("res://addons/platformer_kit/save/save_snapshot.gd")
	const ROOM_RUNTIME := preload("res://addons/platformer_kit/world/runtime/room_runtime.gd")
	const ROOM_03_DATA := "res://resources/rooms/generated/room_03_00.tres"


	func run() -> Array[String]:
		var failures: Array[String] = []
		if not ResourceLoader.exists(SAVE_POINT_SCENE, "PackedScene"):
			return ["reusable SavePoint scene is missing"]
		_assert_scene_contract_and_activation(failures)
		_assert_activation_modes(failures)
		_assert_restored_state_is_visual_and_reusable(failures)
		_assert_room_03_contact_saves(failures)
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


	func _assert_room_03_contact_saves(failures: Array[String]) -> void:
		var room_data: Resource = load(ROOM_03_DATA)
		if room_data == null:
			failures.append("room_03_00 RoomData is missing")
			return
		var runtime: Node2D = ROOM_RUNTIME.new() as Node2D
		add_child(runtime)
		var snapshot: RefCounted = SAVE_SNAPSHOT.new()
		snapshot.world_id = "the_world"
		if not runtime.call("setup_room", room_data, "the_world", snapshot, Vector2i(3, 0)):
			failures.append("room_03_00 runtime content did not load")
			runtime.free()
			return
		var save_point: Node = runtime.call("get_entity", "checkpoint")
		if save_point == null:
			failures.append("room_03_00 runtime has no checkpoint entity")
			runtime.free()
			return
		if save_point.get_node_or_null("VisualRoot") == null:
			failures.append("room_03_00 SavePoint lacks its VisualRoot")
		if int(save_point.get("activation_mode")) != 0:
			failures.append("room_03_00 SavePoint is not in contact mode")
		var actor := Node2D.new()
		save_point.get_node("ActivationArea").emit_signal("body_entered", actor)
		actor.free()
		if not bool(save_point.get("activated")):
			failures.append("room_03_00 SavePoint did not activate on contact")
		if snapshot.respawn_room_id != "room_03_00" or snapshot.respawn_spawn_id != "checkpoint":
			failures.append("room_03_00 SavePoint did not write the respawn identity")
		if not bool(snapshot.get_entity_state("checkpoint").get("activated", false)):
			failures.append("room_03_00 SavePoint did not persist its activated state")
		runtime.free()


## tests/world/test_world_door.gd
class WorldDoorCase extends Node:
	const DOOR_SCENE := "res://addons/platformer_kit/world/entities/world_door.tscn"
	const SAVE_SNAPSHOT := preload("res://addons/platformer_kit/save/save_snapshot.gd")
	const WORLD_DATA := preload("res://addons/platformer_kit/world/data/world_data.gd")


	class FakePortalHost extends Node2D:
		var calls: Array = []
		func travel_to_door(room_id: String, door_id: String) -> bool:
			calls.append([room_id, door_id])
			return true


	class FakeShuttleHost extends Node2D:
		var calls: Array = []
		func travel_to_world(world: Resource, room_id: String, door_id: String) -> bool:
			calls.append([world.world_id if world != null else "", room_id, door_id])
			return true


	func run() -> Array[String]:
		var failures: Array[String] = []
		if not ResourceLoader.exists(DOOR_SCENE, "PackedScene"):
			return ["WorldDoor scene is missing: %s" % DOOR_SCENE]
		_assert_scene_contract(failures)
		_assert_default_arrival_clears_activation_area(failures)
		_assert_activation_persists_and_saves(failures)
		_assert_unlinked_door_refuses_to_travel(failures)
		_assert_portal_dispatch(failures)
		_assert_shuttle_dispatch(failures)
		_assert_interact_mode_uses_the_interactable(failures)
		_assert_arrival_disarm_rearms_after_exit(failures)
		return failures


	func _assert_scene_contract(failures: Array[String]) -> void:
		var door := _make_door({"entity_id": "portal_a"})
		if door == null:
			failures.append("WorldDoor scene could not be instantiated")
			return
		for path: String in ["ActivationArea/CollisionShape2D", "Interactable/CollisionShape2D", "ArrivalSpawn"]:
			if door.get_node_or_null(path) == null:
				failures.append("WorldDoor scene is missing %s" % path)
		var area := door.get_node("ActivationArea") as Area2D
		if area.collision_layer != 0 or area.collision_mask != 2:
			failures.append("WorldDoor activation area does not detect the player collision layer")
		# The player's InteractionDetector finds candidates through area_entered, so
		# the Interactable must stay monitorable.
		var interactable := door.get_node("Interactable") as Area2D
		if interactable.collision_layer != 4:
			failures.append("WorldDoor Interactable is not on the interactable layer")
		if not interactable.monitorable:
			failures.append("WorldDoor Interactable is not monitorable; the player detector cannot see it")
		var arrival := door.get_node("ArrivalSpawn")
		if String(arrival.get("spawn_id")) != "portal_a":
			failures.append("WorldDoor arrival spawn does not answer to the door entity_id")
		if not door.get("persistent"):
			failures.append("WorldDoor is not a persistent entity")
		if door.get("entity_type") != "world_door":
			failures.append("WorldDoor does not declare its entity type")
		door.get_parent().free()


	## The arrival point must not sit inside the door's own sensor, or the actor
	## arrives standing in the door and the pair sends it straight back.
	func _assert_default_arrival_clears_activation_area(failures: Array[String]) -> void:
		var door := _make_door({"entity_id": "portal_a"})
		if door == null:
			return
		var area_node := door.get_node("ActivationArea/CollisionShape2D") as CollisionShape2D
		var area_rect := (area_node.shape as RectangleShape2D).get_rect()
		area_rect.position += area_node.position
		var arrival := (door.get_node("ArrivalSpawn") as Node2D).position
		# The actor body is 6x6 and centred 3px above its origin.
		var player_half := Vector2(3, 3)
		var clearance := Rect2(
			arrival - player_half - Vector2(0.0, 6.0),
			player_half * 2.0
		)
		if clearance.intersects(area_rect):
			failures.append("WorldDoor default arrival spawn overlaps its activation area")
		door.get_parent().free()


	func _assert_activation_persists_and_saves(failures: Array[String]) -> void:
		var snapshot: RefCounted = SAVE_SNAPSHOT.new()
		var host := FakePortalHost.new()
		add_child(host)
		var door := _make_door({
			"entity_id": "portal_a",
			"target_room_id": "room_b",
			"target_door_id": "portal_b",
		}, host, snapshot)
		if door == null:
			host.free()
			return
		var requests: Array[bool] = []
		door.save_requested.connect(func(immediate: bool) -> void: requests.append(immediate))
		if not bool(door.call("activate", null)):
			failures.append("WorldDoor refused a configured portal activation")
		if not bool(door.get("activated")):
			failures.append("WorldDoor did not activate")
		if not bool(snapshot.get_entity_state("world_a:room_a:portal_a").get("activated", false)):
			failures.append("WorldDoor did not persist its activated state")
		if requests != [false]:
			failures.append("WorldDoor did not queue exactly one deferred save")
		if host.calls != [["room_b", "portal_b"]]:
			failures.append("WorldDoor did not ask its host to travel to the partner door")
		if bool(door.call("activate", null)):
			failures.append("WorldDoor travelled twice without leaving the door")
		host.free()


	func _assert_unlinked_door_refuses_to_travel(failures: Array[String]) -> void:
		var snapshot: RefCounted = SAVE_SNAPSHOT.new()
		var host := FakePortalHost.new()
		add_child(host)
		var door := _make_door({"entity_id": "orphan"}, host, snapshot)
		if door == null:
			host.free()
			return
		if bool(door.call("activate", null)):
			failures.append("WorldDoor activated without a configured link")
		if not host.calls.is_empty() or bool(door.get("activated")):
			failures.append("WorldDoor mutated state for an unlinked activation")
		host.free()


	func _assert_portal_dispatch(failures: Array[String]) -> void:
		var snapshot: RefCounted = SAVE_SNAPSHOT.new()
		var host := FakePortalHost.new()
		add_child(host)
		var door := _make_door({
			"entity_id": "portal_a",
			"door_kind": 0,
			"target_room_id": "room_b",
			"target_door_id": "portal_b",
		}, host, snapshot)
		if door == null:
			host.free()
			return
		if not bool(door.call("activate", null)):
			failures.append("PORTAL door did not travel")
		if host.calls.size() != 1:
			failures.append("PORTAL door did not use the in-world travel path")
		host.free()


	func _assert_shuttle_dispatch(failures: Array[String]) -> void:
		var snapshot: RefCounted = SAVE_SNAPSHOT.new()
		var host := FakeShuttleHost.new()
		add_child(host)
		var other_world: Resource = WORLD_DATA.new()
		other_world.world_id = "world_b"
		var door := _make_door({
			"entity_id": "shuttle_a",
			"door_kind": 1,
			"target_world": other_world,
			"target_room_id": "room_b",
			"target_door_id": "shuttle_b",
		}, host, snapshot)
		if door == null:
			host.free()
			return
		if String(door.call("get_target_world_id")) != "world_b":
			failures.append("SHUTTLE door does not expose its target world id")
		if not bool(door.call("activate", null)):
			failures.append("SHUTTLE door did not travel")
		if host.calls != [["world_b", "room_b", "shuttle_b"]]:
			failures.append("SHUTTLE door did not use the cross-world travel path")
		host.free()


	## INTERACT mode is driven by the door's Interactable area; CONTACT mode keeps
	## that area disabled so a player prompt never appears for it.
	func _assert_interact_mode_uses_the_interactable(failures: Array[String]) -> void:
		var snapshot: RefCounted = SAVE_SNAPSHOT.new()
		var host := FakePortalHost.new()
		add_child(host)
		var door := _make_door({
			"entity_id": "interact_a",
			"activation_mode": 1,
			"target_room_id": "room_b",
			"target_door_id": "interact_b",
		}, host, snapshot)
		if door == null:
			host.free()
			return
		var interactable := door.get_node_or_null("Interactable")
		if interactable == null:
			failures.append("INTERACT door has no Interactable area")
		elif not bool(interactable.get("enabled")):
			failures.append("INTERACT door did not enable its Interactable area")
		else:
			interactable.call("interact", null)
			if host.calls != [["room_b", "interact_b"]]:
				failures.append("INTERACT door did not travel when its Interactable fired")
		var contact := _make_door({
			"entity_id": "contact_a",
			"activation_mode": 0,
			"target_room_id": "room_b",
			"target_door_id": "contact_b",
		}, host, snapshot)
		if contact != null:
			var contact_area := contact.get_node_or_null("Interactable")
			if contact_area != null and bool(contact_area.get("enabled")):
				failures.append("CONTACT door left its Interactable area enabled")
		host.free()


	func _assert_arrival_disarm_rearms_after_exit(failures: Array[String]) -> void:
		var snapshot: RefCounted = SAVE_SNAPSHOT.new()
		var host := FakePortalHost.new()
		add_child(host)
		var door := _make_door({
			"entity_id": "portal_a",
			"target_room_id": "room_b",
			"target_door_id": "portal_b",
		}, host, snapshot)
		if door == null:
			host.free()
			return
		door.call("set_arrival_disarmed")
		if bool(door.call("is_armed")) or bool(door.call("activate", null)):
			failures.append("disarmed arrival door still travelled")
		for _index: int in range(WorldDoor.REARM_FRAMES + 1):
			door.call("_physics_process", 0.016)
		if not bool(door.call("is_armed")):
			failures.append("arrival door did not re-arm after the actor stepped out")
		if not bool(door.call("activate", null)):
			failures.append("re-armed arrival door refused a new trip")
		host.free()


	func _make_door(values: Dictionary, host: Node = null, snapshot: RefCounted = null) -> Node:
		var packed := load(DOOR_SCENE) as PackedScene
		if packed == null:
			return null
		var door := packed.instantiate()
		for key: String in values:
			door.set(key, values[key])
		var parent: Node = host
		if parent == null:
			parent = Node2D.new()
			add_child(parent)
		parent.add_child(door)
		door.set("persistent", true)
		door.call("setup_entity", {
			"world_id": "world_a",
			"room_id": "room_a",
			"entity_state_sink": snapshot if snapshot != null else SAVE_SNAPSHOT.new(),
		})
		return door


## tests/world/test_killzone.gd
class KillzoneCase extends Node:
	class FakePlayer:
		extends Node2D
		var spawn_position := Vector2(68, 140)
		var events: Array[String] = []

		func respawn_at(target: Vector2) -> void:
			global_position = target
			events.append("respawn")

		func play_hurt_effect() -> void:
			events.append("hurt:%s" % str(global_position))


	class RespawnOnlyPlayer:
		extends Node2D
		var respawn_count := 0

		func respawn_at(_target: Vector2) -> void:
			respawn_count += 1


	class RespawnWithoutHurtPlayer:
		extends Node2D
		var spawn_position := Vector2(32, 96)
		var respawn_count := 0

		func respawn_at(target: Vector2) -> void:
			global_position = target
			respawn_count += 1


	func run() -> Array[String]:
		var failures: Array[String] = []
		var packed := load("res://scenes/world/killzone.tscn") as PackedScene
		if packed == null:
			return ["reusable Killzone scene is missing"]
		var zone := packed.instantiate() as Area2D
		add_child(zone)
		if zone.collision_layer != 0 or zone.collision_mask != 2:
			failures.append("Killzone must detect player collision layer 2")
		var player := FakePlayer.new()
		player.add_to_group("player")
		add_child(player)
		zone.body_entered.emit(player)
		var expected := ["respawn", "hurt:%s" % str(player.spawn_position)]
		if player.events != expected:
			failures.append("Killzone must respawn before hurt feedback: %s" % str(player.events))
		var bystander := Node2D.new()
		add_child(bystander)
		zone.body_entered.emit(bystander)
		if player.events.size() != 2:
			failures.append("non-player contact retriggered Killzone")
		var invalid_player := RespawnOnlyPlayer.new()
		invalid_player.add_to_group("player")
		add_child(invalid_player)
		zone.body_entered.emit(invalid_player)
		if invalid_player.respawn_count != 0:
			failures.append("player without spawn_position should be ignored")
		var player_without_hurt := RespawnWithoutHurtPlayer.new()
		player_without_hurt.add_to_group("player")
		add_child(player_without_hurt)
		zone.body_entered.emit(player_without_hurt)
		if player_without_hurt.respawn_count != 1 or player_without_hurt.global_position != player_without_hurt.spawn_position:
			failures.append("missing hurt-effect interface must not block respawn")
		zone.free()
		player.free()
		bystander.free()
		invalid_player.free()
		player_without_hurt.free()
		return failures


## tests/world/test_spike_hazard.gd
class SpikeHazardCase extends Node:
	## Atlas (0,8) is the spike. Its alternatives rotate it, every spike cell gets a
	## half-tile Killzone, and touching one returns the player to `spawn_position`.

	const BUILDER_PATH := "res://scripts/world/spike_hazard_area_builder.gd"
	const TILESET_PATH := "res://resources/tilesets/primordial_tileset.tres"
	const TEMPLATE_PATH := "res://scenes/rooms/template/level_template.tscn"
	const ROOM_PATH := "res://scenes/levels/the_world/room_01_00.tscn"
	const ROOM_BAKER := preload("res://addons/world_editor/authoring/room/room_baker.gd")
	const SPIKE := Vector2i(0, 8)


	class FakePlayer:
		extends Node2D
		var spawn_position := Vector2(40, 56)
		var events: Array[String] = []

		func respawn_at(target: Vector2) -> void:
			global_position = target
			events.append("respawn")

		func play_hurt_effect() -> void:
			events.append("hurt:%s" % str(global_position))


	func run() -> Array[String]:
		var failures: Array[String] = []
		_assert_tileset(failures)
		_assert_builder_geometry(failures)
		_assert_contact_respawns(failures)
		_assert_template_and_bake(failures)
		return failures


	func _assert_tileset(failures: Array[String]) -> void:
		var tile_set := load(TILESET_PATH) as TileSet
		if tile_set == null:
			failures.append("primordial tileset could not be loaded")
			return
		var source := tile_set.get_source(0) as TileSetAtlasSource
		if source == null or not source.has_tile(SPIKE):
			failures.append("the spike tile %s is missing" % SPIKE)
			return
		if source.get_alternative_tiles_count(SPIKE) != 4:
			failures.append("the spike must have four alternatives")
			return
		var expected_flags: Array[Array] = [
			[false, false, false],
			[true, false, true],
			[true, true, false],
			[false, true, true],
		]
		for index: int in 4:
			var alternative_id := source.get_alternative_tile_id(SPIKE, index)
			if alternative_id != index:
				failures.append("spike alternative %d has id %d" % [index, alternative_id])
				continue
			var data := source.get_tile_data(SPIKE, alternative_id)
			if data == null:
				failures.append("spike alternative %d has no TileData" % index)
				continue
			var flags: Array = expected_flags[index]
			if data.flip_h != bool(flags[0]) or data.flip_v != bool(flags[1]) or data.transpose != bool(flags[2]):
				failures.append("spike alternative %d has flags %s/%s/%s" % [
					index, data.flip_h, data.flip_v, data.transpose,
				])
			if data.get_collision_polygons_count(0) != 0:
				failures.append("spike alternative %d must not have solid collision" % index)


	func _assert_builder_geometry(failures: Array[String]) -> void:
		var builder := _build_spike_terrain(failures)
		if builder == null:
			return
		if builder.get_child_count() != 4:
			failures.append("expected four spike zones, found %d" % builder.get_child_count())
		var expected := {
			"SpikeZone_0_0": [Vector2(324, 6), Vector2(8, 4)],
			"SpikeZone_1_0": [Vector2(330, 4), Vector2(4, 8)],
			"SpikeZone_2_0": [Vector2(340, 2), Vector2(8, 4)],
			"SpikeZone_3_0": [Vector2(350, 4), Vector2(4, 8)],
		}
		for zone_name: String in expected:
			var zone := builder.get_node_or_null(zone_name) as Area2D
			if zone == null:
				failures.append("missing spike zone %s" % zone_name)
				continue
			var wanted: Array = expected[zone_name]
			if not zone.global_position.is_equal_approx(wanted[0]):
				failures.append("%s is at %s, expected %s" % [zone_name, zone.global_position, wanted[0]])
			var shape := zone.get_node("CollisionShape2D").shape as RectangleShape2D
			if shape == null or not shape.size.is_equal_approx(wanted[1]):
				failures.append("%s has the wrong trigger size" % zone_name)
			if zone.collision_layer != 0 or zone.collision_mask != 2:
				failures.append("%s must only detect collision layer 2" % zone_name)
		builder.get_parent().free()


	func _assert_contact_respawns(failures: Array[String]) -> void:
		var builder := _build_spike_terrain(failures)
		if builder == null:
			return
		var zone := builder.get_node_or_null("SpikeZone_0_0") as Area2D
		if zone == null:
			failures.append("no spike zone to test contact")
			builder.get_parent().free()
			return
		var player := FakePlayer.new()
		player.add_to_group("player")
		add_child(player)
		zone.body_entered.emit(player)
		var expected := ["respawn", "hurt:%s" % str(player.spawn_position)]
		if player.events != expected:
			failures.append("spike must respawn before hurt, got %s" % str(player.events))
		var bystander := Node2D.new()
		add_child(bystander)
		zone.body_entered.emit(bystander)
		if player.events.size() != 2:
			failures.append("a non-player body retriggered the spike")
		player.free()
		bystander.free()
		builder.get_parent().free()


	func _assert_template_and_bake(failures: Array[String]) -> void:
		if not ResourceLoader.exists(BUILDER_PATH):
			failures.append("spike hazard builder is missing")
			return
		var builder_script := load(BUILDER_PATH) as Script
		var template := load(TEMPLATE_PATH) as PackedScene
		if template == null:
			failures.append("level template could not be loaded")
			return
		var template_root := template.instantiate()
		var template_builder := template_root.get_node_or_null("RoomContent/Terrain/SpikeHazardAreaBuilder")
		if template_builder == null or template_builder.get_script() != builder_script:
			failures.append("level template has no SpikeHazardAreaBuilder")
		template_root.free()
		var room := (load(ROOM_PATH) as PackedScene).instantiate()
		if room.get_node_or_null("RoomContent/Terrain/SpikeHazardAreaBuilder") == null:
			failures.append("room_01_00 did not inherit the spike hazard builder")
		var staged: Dictionary = ROOM_BAKER.new().stage(room, ROOM_PATH)
		if not staged.get("ok", false):
			failures.append("room_01_00 could not stage: %s" % staged.get("errors", []))
		else:
			var terrain := (staged["terrain_scene"] as PackedScene).instantiate()
			var baked_builder := terrain.get_node_or_null("Terrain/SpikeHazardAreaBuilder")
			if baked_builder == null:
				failures.append("baked terrain lost the spike hazard builder")
			elif baked_builder.get_child_count() != 0:
				failures.append("runtime spike zones were serialized into baked terrain")
			terrain.free()
		room.free()


	func _build_spike_terrain(failures: Array[String]) -> Node2D:
		if not ResourceLoader.exists(BUILDER_PATH):
			failures.append("spike hazard builder is missing")
			return null
		var builder_script := load(BUILDER_PATH) as Script
		var tiles := load(TILESET_PATH) as TileSet
		if tiles == null:
			failures.append("primordial tileset could not be loaded")
			return null
		var terrain := Node2D.new()
		add_child(terrain)
		terrain.position = Vector2(320, 0)
		var layer := TileMapLayer.new()
		layer.tile_set = tiles
		terrain.add_child(layer)
		for index: int in 4:
			layer.set_cell(Vector2i(index, 0), 0, SPIKE, index)
		var builder := builder_script.new() as Node2D
		terrain.add_child(builder)
		return builder


## tests/world/test_ladder_tiles.gd
class LadderTilesCase extends Node:
	const BUILDER_PATH := "res://scripts/world/ladder_tile_area_builder.gd"
	const TILESET_PATH := "res://resources/tilesets/primordial_tileset.tres"
	const ROOM_BAKER := preload("res://addons/world_editor/authoring/room/room_baker.gd")


	func run() -> Array[String]:
		var failures: Array[String] = []
		var script := load(BUILDER_PATH) as Script
		if script == null:
			return ["ladder tile area builder is missing"]
		var terrain := Node2D.new()
		add_child(terrain)
		terrain.position = Vector2(320, 0)
		var tiles := load(TILESET_PATH) as TileSet
		var layer := TileMapLayer.new()
		layer.tile_set = tiles
		terrain.add_child(layer)
		layer.set_cell(Vector2i(0, 0), 0, Vector2i(0, 7), 0)
		layer.set_cell(Vector2i(1, 0), 0, Vector2i(0, 7), 1)
		layer.set_cell(Vector2i(2, 0), 0, Vector2i(0, 6), 0)
		var builder := script.new() as Node2D
		terrain.add_child(builder)
		if builder.get_child_count() != 1:
			failures.append("adjacent ladder cells must merge into one zone")
		for zone: Node in builder.get_children():
			if not zone.is_in_group("ladder_zone") or (zone as Area2D).collision_layer != 4:
				failures.append("generated zone has wrong group or trigger layer")
			var shape := zone.get_node("CollisionShape2D").shape as RectangleShape2D
			if shape.size != Vector2(16, 8):
				failures.append("merged ladder zone has wrong rectangle size")
		var first := builder.get_child(0) as Node2D
		if first.global_position != layer.to_global(layer.map_to_local(Vector2i.ZERO) + Vector2(4, 0)):
			failures.append("merged ladder zone position does not match its rectangle center")
		builder.call("rebuild")
		if builder.get_child_count() != 1:
			failures.append("rebuild duplicated or lost merged ladder zones")
		terrain.free()
		_assert_template_and_room_bake(script, failures)
		_assert_baked_output(failures)
		return failures


	func _assert_template_and_room_bake(script: Script, failures: Array[String]) -> void:
		var template := load("res://scenes/rooms/template/level_template.tscn") as PackedScene
		if template == null:
			failures.append("level template is missing")
			return
		var template_root := template.instantiate()
		if template_root.get_node_or_null("RoomContent/Terrain/LadderAreaBuilder") == null:
			failures.append("level template has no LadderAreaBuilder")
		template_root.free()
		var room_path := "res://scenes/levels/the_world/room_01_00.tscn"
		var packed := load(room_path) as PackedScene
		if packed == null:
			failures.append("room_01_00 is missing")
			return
		var preview := packed.instantiate()
		add_child(preview)
		var source_builder := preview.get_node_or_null("RoomContent/Terrain/LadderAreaBuilder")
		if source_builder == null or source_builder.get_script() != script:
			failures.append("room_01_00 did not inherit the ladder builder")
		elif source_builder.get_child_count() == 0:
			failures.append("user ladder tiles did not generate any runtime zones")
		preview.free()
		var source := packed.instantiate()
		var staged: Dictionary = ROOM_BAKER.new().stage(source, room_path)
		if not staged.get("ok", false):
			failures.append("room_01_00 could not stage ladder terrain: %s" % staged.get("errors", []))
		else:
			var terrain := (staged["terrain_scene"] as PackedScene).instantiate()
			var baked_builder := terrain.get_node_or_null("Terrain/LadderAreaBuilder")
			if baked_builder == null:
				failures.append("baked terrain lost ladder builder")
			elif baked_builder.get_child_count() != 0:
				failures.append("runtime ladder zones were serialized into baked terrain")
			add_child(terrain)
			if baked_builder != null and baked_builder.get_child_count() == 0:
				failures.append("baked terrain did not generate zones at runtime")
			terrain.free()
		source.free()


	func _assert_baked_output(failures: Array[String]) -> void:
		var packed := load("res://scenes/rooms/generated/room_01_00/terrain.tscn") as PackedScene
		if packed == null:
			failures.append("baked room_01_00 terrain is missing")
			return
		var terrain := packed.instantiate()
		add_child(terrain)
		var builder := terrain.get_node_or_null("Terrain/LadderAreaBuilder")
		if builder == null or builder.get_child_count() == 0:
			failures.append("saved baked terrain has no runtime ladder zones")
		var expected_uids := {
			"res://resources/rooms/generated/room_01_00.tres": "uid://cu73ap10eduij",
			"res://scenes/rooms/generated/room_01_00/runtime.tscn": "uid://wxounvpgtvcs",
			"res://scenes/rooms/generated/room_01_00/terrain.tscn": "uid://dfsicbqifkxqn",
		}
		for path: String in expected_uids:
			var first_line := FileAccess.get_file_as_string(path).get_slice("\n", 0)
			if not first_line.contains(expected_uids[path]):
				failures.append("room bake did not preserve resource UID: %s" % path)
		terrain.free()


## tests/world/test_phantom_wall.gd
class PhantomWallCase extends Node:
	## A phantom wall is a TileMapLayer that looks like terrain, does not collide,
	## blocks sight while it stands, and dissolves when a character touches it.

	const WALL_SCENE: PackedScene = preload("res://scenes/world/phantom_wall.tscn")
	const BLOCK_TILE := Vector2i(0, 0)


	class FakeFog extends Node:
		var refreshes := 0

		func _ready() -> void:
			add_to_group(&"fog_of_war")

		func request_refresh() -> void:
			refreshes += 1


	func run() -> Array[String]:
		var failures: Array[String] = []
		var fog := FakeFog.new()
		add_child(fog)
		var wall := WALL_SCENE.instantiate() as TileMapLayer
		wall.position = Vector2(32.0, 48.0)
		wall.set_cell(Vector2i(0, 0), 0, BLOCK_TILE)
		wall.set_cell(Vector2i(0, 1), 0, BLOCK_TILE)
		add_child(wall)
		if wall.collision_enabled:
			failures.append("phantom wall layer must not collide")
		if not bool(wall.call("is_occluding")):
			failures.append("phantom wall does not block sight before it is revealed")
		if wall.call("get_world_rect") != Rect2(32.0, 48.0, 8.0, 16.0):
			failures.append("phantom wall footprint does not follow its painted cells")
		if wall.call("get_tile_layer") != wall:
			failures.append("phantom wall did not resolve its own tile layer")
		if wall.call("get_sense") == null:
			failures.append("phantom wall did not build its contact area")
		wall.set("fade_seconds", 0.0)
		if not bool(wall.call("reveal")):
			failures.append("phantom wall refused to reveal")
		if bool(wall.call("is_occluding")):
			failures.append("revealed phantom wall still blocks sight")
		if wall.visible:
			failures.append("revealed phantom wall is still drawn")
		if fog.refreshes < 1:
			failures.append("revealing the phantom wall did not refresh the fog")
		if bool(wall.call("reveal")):
			failures.append("phantom wall revealed twice")
		wall.call("reset_component")
		if not wall.visible or not bool(wall.call("is_occluding")):
			failures.append("reset_component did not restore the phantom wall")
		wall.free()
		fog.free()
		return failures


## tests/world/test_fog_door.gd
class FogDoorCase extends Node:
	## The fog door is composed from components now: a solid body, DoorComponent2D
	## and FogOccluderComponent2D. Opening it must clear both the collision and the
	## sight blocker; closing it must restore both.

	const DOOR_SCENE: PackedScene = preload("res://scenes/world/fog_door.tscn")
	const RETIRED_SCRIPT := "res://scripts/world/fog_door.gd"
	const DOOR_SIZE := Vector2(8.0, 16.0)


	func run() -> Array[String]:
		var failures: Array[String] = []
		if FileAccess.file_exists(RETIRED_SCRIPT):
			failures.append("the bespoke FogDoor script still exists")
		var door := DOOR_SCENE.instantiate() as Node2D
		door.position = Vector2(32.0, 48.0)
		add_child(door)
		var body := door.get_node("Body") as StaticBody2D
		var shape := door.get_node("Body/CollisionShape2D") as CollisionShape2D
		var component := door.get_node("Door")
		var occluder := door.get_node("FogOccluder")
		if not bool(component.call("is_closed")):
			failures.append("door does not start closed")
		if not bool(occluder.call("is_occluding")):
			failures.append("closed door does not occlude sight")
		if occluder.call("get_world_rect") != Rect2(Vector2(32.0, 48.0), DOOR_SIZE):
			failures.append("door occluder rect does not match its cell size")
		if shape.disabled:
			failures.append("closed door collision is disabled")
		if body.collision_layer != 1:
			failures.append("closed door body is not solid")
		component.call("set_closed", false)
		if bool(component.call("is_closed")):
			failures.append("door did not open")
		if bool(occluder.call("is_occluding")):
			failures.append("open door still occludes sight")
		if not shape.disabled:
			failures.append("open door collision is still enabled")
		if body.collision_layer != 0:
			failures.append("open door body stayed solid")
		component.call("set_closed", true)
		if shape.disabled:
			failures.append("door did not restore its collision after closing")
		if not bool(occluder.call("is_occluding")):
			failures.append("closed door did not restore its sight blocker")
		component.set("blocks_sight", false)
		component.call("set_closed", false)
		component.call("set_closed", true)
		if bool(occluder.call("is_occluding")):
			failures.append("a see-through door occluded sight")
		component.set("blocks_sight", true)
		component.call("set_closed", false)
		component.call("set_closed", true)
		if not bool(occluder.call("is_occluding")):
			failures.append("restoring blocks_sight did not restore occlusion")
		component.set("size_cells", Vector2i(2, 3))
		if occluder.call("get_world_rect") != Rect2(Vector2(32.0, 48.0), Vector2(16.0, 24.0)):
			failures.append("resizing the door did not resize its sight blocker")
		if (body.get_parent() as Node) != door:
			failures.append("door body left the door node")
		door.free()
		return failures


## tests/world/test_crumble_runtime.gd
class CrumbleRuntimeCase extends Node:
	const CRUMBLE_RUNTIME: Script = preload("res://scripts/world/crumble_runtime.gd")
	const ROOM_DATA: Script = preload("res://addons/platformer_kit/world/data/room_data.gd")

	const CELL := Vector2i(3, 2)
	const CRUMBLE_SOLID := Vector2i(3, 0)
	const CRUMBLE_ONE_WAY := Vector2i(3, 4)
	const PLAIN := Vector2i(0, 0)


	func run() -> Array[String]:
		var failures: Array[String] = []
		_assert_shake_break_respawn(failures)
		_assert_room_rebind_restores_broken_cell(failures)
		_assert_both_crumble_tiles_are_driven(failures)
		_assert_clear_room_restores(failures)
		_assert_plain_tiles_are_ignored(failures)
		return failures


	func _assert_shake_break_respawn(failures: Array[String]) -> void:
		var terrain := _make_terrain()
		add_child(terrain)
		var runtime: Node2D = CRUMBLE_RUNTIME.new() as Node2D
		add_child(runtime)
		var room: Resource = _make_room()
		if not bool(runtime.call("bind_room_with_origin", room, terrain, Vector2i.ZERO)):
			failures.append("crumble runtime rejected a valid terrain binding")
			terrain.free()
			runtime.free()
			return
		var layer := terrain.get_node("Terrain/SolidTiles") as TileMapLayer
		layer.set_cell(CELL, 0, CRUMBLE_SOLID)
		if not bool(runtime.call("trigger_cell", layer, CELL)):
			failures.append("crumble runtime did not accept a cell trigger")
		runtime.call("tick", 0.1)
		if layer.get_cell_source_id(CELL) == -1:
			failures.append("cell was erased before the shake finished")
		runtime.call("tick", 0.2)
		if layer.get_cell_source_id(CELL) != -1:
			failures.append("cell was not erased after the shake")
		runtime.call("tick", 1.6)
		if layer.get_cell_source_id(CELL) == -1:
			failures.append("cell was not written back after the respawn delay")
		terrain.free()
		runtime.free()


	func _assert_room_rebind_restores_broken_cell(failures: Array[String]) -> void:
		var first := _make_terrain()
		var second := _make_terrain()
		add_child(first)
		add_child(second)
		var runtime: Node2D = CRUMBLE_RUNTIME.new() as Node2D
		add_child(runtime)
		runtime.call("bind_room_with_origin", _make_room(), first, Vector2i.ZERO)
		var layer := first.get_node("Terrain/SolidTiles") as TileMapLayer
		layer.set_cell(CELL, 0, CRUMBLE_SOLID)
		runtime.call("trigger_cell", layer, CELL)
		runtime.call("tick", 0.3)
		if layer.get_cell_source_id(CELL) != -1:
			failures.append("cell was not erased before the room switch")
		runtime.call("bind_room_with_origin", _make_room(), second, Vector2i(1, 0))
		if layer.get_cell_source_id(CELL) == -1:
			failures.append("room switch did not restore the broken cell in the old room")
		first.free()
		second.free()
		runtime.free()


	func _assert_both_crumble_tiles_are_driven(failures: Array[String]) -> void:
		var terrain := _make_terrain()
		add_child(terrain)
		var runtime: Node2D = CRUMBLE_RUNTIME.new() as Node2D
		add_child(runtime)
		runtime.call("bind_room_with_origin", _make_room(), terrain, Vector2i.ZERO)
		var solid := terrain.get_node("Terrain/SolidTiles") as TileMapLayer
		solid.set_cell(Vector2i(1, 1), 0, CRUMBLE_SOLID)
		solid.set_cell(Vector2i(2, 1), 0, CRUMBLE_ONE_WAY)
		runtime.call("trigger_cell", solid, Vector2i(1, 1))
		runtime.call("trigger_cell", solid, Vector2i(2, 1))
		runtime.call("tick", 0.3)
		if solid.get_cell_source_id(Vector2i(1, 1)) != -1:
			failures.append("solid crumble tile was not driven")
		if solid.get_cell_source_id(Vector2i(2, 1)) != -1:
			failures.append("one-way crumble tile was not driven")
		terrain.free()
		runtime.free()


	func _assert_clear_room_restores(failures: Array[String]) -> void:
		var terrain := _make_terrain()
		add_child(terrain)
		var runtime: Node2D = CRUMBLE_RUNTIME.new() as Node2D
		add_child(runtime)
		runtime.call("bind_room_with_origin", _make_room(), terrain, Vector2i.ZERO)
		var layer := terrain.get_node("Terrain/SolidTiles") as TileMapLayer
		layer.set_cell(CELL, 0, CRUMBLE_SOLID)
		runtime.call("trigger_cell", layer, CELL)
		runtime.call("tick", 0.3)
		runtime.call("clear_room")
		if layer.get_cell_source_id(CELL) == -1:
			failures.append("clear_room did not restore the erased crumble cell")
		terrain.free()
		runtime.free()


	func _assert_plain_tiles_are_ignored(failures: Array[String]) -> void:
		var terrain := _make_terrain()
		add_child(terrain)
		var runtime: Node2D = CRUMBLE_RUNTIME.new() as Node2D
		add_child(runtime)
		runtime.call("bind_room_with_origin", _make_room(), terrain, Vector2i.ZERO)
		var layer := terrain.get_node("Terrain/SolidTiles") as TileMapLayer
		layer.set_cell(CELL, 0, PLAIN)
		if bool(runtime.call("trigger_cell", layer, CELL)):
			failures.append("a non-crumble tile started shaking")
		terrain.free()
		runtime.free()


	func _make_room() -> Resource:
		var room: Resource = ROOM_DATA.new()
		room.room_id = "crumble_test"
		room.room_size_chunks = Vector2i.ONE
		return room


	func _make_terrain() -> Node2D:
		var root := Node2D.new()
		var terrain := Node2D.new()
		terrain.name = "Terrain"
		root.add_child(terrain)
		var tile_set := _make_tileset()
		for layer_name: String in ["BackTiles", "SolidTiles", "DetailTiles"]:
			var layer := TileMapLayer.new()
			layer.name = layer_name
			layer.tile_set = tile_set
			layer.collision_enabled = layer_name == "SolidTiles"
			terrain.add_child(layer)
		return root


	func _make_tileset() -> TileSet:
		var tile_set := TileSet.new()
		tile_set.tile_size = Vector2i(8, 8)
		tile_set.add_physics_layer()
		var source := TileSetAtlasSource.new()
		var image := Image.create(32, 64, false, Image.FORMAT_RGBA8)
		image.fill(Color.WHITE)
		source.texture = ImageTexture.create_from_image(image)
		source.texture_region_size = Vector2i(8, 8)
		for coords: Vector2i in [PLAIN, CRUMBLE_SOLID, CRUMBLE_ONE_WAY]:
			source.create_tile(coords)
		tile_set.add_source(source, 0)
		return tile_set


func run() -> Array[String]:
	var failures: Array[String] = []
	failures.append_array(_run_case(WorldEntityCase.new()))
	failures.append_array(_run_case(SavePointCase.new()))
	failures.append_array(_run_case(WorldDoorCase.new()))
	failures.append_array(_run_case(KillzoneCase.new()))
	failures.append_array(_run_case(SpikeHazardCase.new()))
	failures.append_array(_run_case(LadderTilesCase.new()))
	failures.append_array(_run_case(PhantomWallCase.new()))
	failures.append_array(_run_case(FogDoorCase.new()))
	failures.append_array(_run_case(CrumbleRuntimeCase.new()))
	return failures


func _run_case(test: Node) -> Array[String]:
	add_child(test)
	var result: Array = test.call("run")
	test.queue_free()
	var failures: Array[String] = []
	failures.assign(result)
	return failures
