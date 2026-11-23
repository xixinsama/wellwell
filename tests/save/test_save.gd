extends Node

## Merged test suite. Every inner class below is one original test file,
## kept in its own class so fixtures and helper names stay isolated. Do not
## add logic here: split a class back into its own file when it grows.

## tests/save/test_save_codec.gd
class SaveCodecCase extends Node:
	const SAVE_SNAPSHOT: Script = preload("res://addons/platformer_kit/save/save_snapshot.gd")
	const SAVE_CODEC: Script = preload("res://addons/platformer_kit/save/save_codec.gd")
	const SAVE_MANAGER: Script = preload("res://addons/platformer_kit/save/save_manager.gd")


	class RecordingStorage extends RefCounted:
		var written: RefCounted

		func write_slot(snapshot: RefCounted) -> bool:
			written = snapshot
			return true


	func run() -> Array[String]:
		var failures: Array[String] = []
		_assert_respawn_updates_are_validated(failures)
		_assert_round_trip_preserves_module_state(failures)
		_assert_invalid_data_is_rejected(failures)
		_assert_invalid_load_does_not_mutate_existing_snapshot(failures)
		_assert_commits_announce_the_snapshot_before_writing(failures)
		_assert_resume_state_round_trip(failures)
		_assert_invalid_resume_state_is_optional(failures)
		return failures


	func _assert_respawn_updates_are_validated(failures: Array[String]) -> void:
		var snapshot: RefCounted = SAVE_SNAPSHOT.new()
		snapshot.respawn_room_id = "old_room"
		snapshot.respawn_spawn_id = "old_spawn"
		snapshot.respawn_position = Vector2(4, 8)
		if not snapshot.has_method("set_respawn"):
			failures.append("SaveSnapshot is missing validated set_respawn")
			return
		if snapshot.call("set_respawn", "", "checkpoint", Vector2.ZERO):
			failures.append("SaveSnapshot accepted an empty respawn room id")
		if snapshot.call("set_respawn", "room_a", "", Vector2.ZERO):
			failures.append("SaveSnapshot accepted an empty respawn spawn id")
		if snapshot.call("set_respawn", "room_a", "checkpoint", Vector2(INF, 0)):
			failures.append("SaveSnapshot accepted a non-finite respawn position")
		if snapshot.respawn_room_id != "old_room" or snapshot.respawn_position != Vector2(4, 8):
			failures.append("invalid respawn data mutated the snapshot")
		if not snapshot.call("set_respawn", "room_a", "checkpoint", Vector2(12, 24)):
			failures.append("SaveSnapshot rejected valid respawn data")
		elif snapshot.respawn_room_id != "room_a" or snapshot.respawn_spawn_id != "checkpoint" or snapshot.respawn_position != Vector2(12, 24):
			failures.append("SaveSnapshot did not apply valid respawn data atomically")


	func _assert_round_trip_preserves_module_state(failures: Array[String]) -> void:
		var snapshot: RefCounted = SAVE_SNAPSHOT.new()
		snapshot.slot = 1
		snapshot.respawn_position = Vector2(-120, 48)
		snapshot.set_module_state(&"test_module", {"visited": ["room_a"]})
		var codec: RefCounted = SAVE_CODEC.new()

		var decoded: RefCounted = codec.decode(codec.encode(snapshot), 1)

		if decoded == null:
			failures.append("decoded snapshot was null")
			return
		if decoded.slot != 1:
			failures.append("slot did not round trip")
		if decoded.respawn_position != Vector2(-120, 48):
			failures.append("respawn position did not round trip")
		if decoded.get_module_state(&"test_module") != {"visited": ["room_a"]}:
			failures.append("generic module state did not round trip")


	func _assert_invalid_data_is_rejected(failures: Array[String]) -> void:
		var codec: RefCounted = SAVE_CODEC.new()
		if codec.decode("{not valid json", 1) != null:
			failures.append("invalid JSON decoded")
		if codec.decode("[]", 1) != null:
			failures.append("non-dictionary JSON decoded")
		var snapshot: RefCounted = SAVE_SNAPSHOT.new()
		snapshot.slot = 2
		if codec.decode(codec.encode(snapshot), 1) != null:
			failures.append("mismatched slot decoded")


	func _assert_invalid_load_does_not_mutate_existing_snapshot(failures: Array[String]) -> void:
		var snapshot: RefCounted = SAVE_SNAPSHOT.new()
		snapshot.slot = 1
		snapshot.world_id = "preserved_world"
		snapshot.set_module_state(&"preserved_module", {"active": true})
		snapshot.set_entity_state("preserved:entity", {"active": true})
		var invalid_data: Dictionary = snapshot.to_dictionary()
		invalid_data["world_id"] = "invalid_world"
		invalid_data["module_states"] = {"replacement_module": {"active": true}}
		invalid_data["entity_states"] = {"replacement:entity": "not_a_dictionary"}
		if snapshot.load_from_dictionary(invalid_data) != null:
			failures.append("snapshot accepted invalid entity state data")
			return
		if snapshot.world_id != "preserved_world":
			failures.append("invalid load mutated snapshot metadata")
		if not bool(snapshot.get_module_state(&"preserved_module").get("active", false)) or not snapshot.get_module_state(&"replacement_module").is_empty():
			failures.append("invalid load mutated module states")
		if not bool(snapshot.get_entity_state("preserved:entity").get("active", false)):
			failures.append("invalid load mutated entity states")


	func _assert_commits_announce_the_snapshot_before_writing(failures: Array[String]) -> void:
		var manager: Node = SAVE_MANAGER.new()
		var storage := RecordingStorage.new()
		var snapshot: RefCounted = SAVE_SNAPSHOT.new()
		snapshot.slot = 1
		manager.setup_storage(storage)
		manager.current_snapshot = snapshot
		if not manager.has_signal("snapshot_committing"):
			failures.append("SaveManager must announce a snapshot before writing it")
		else:
			manager.connect("snapshot_committing", func(target: RefCounted) -> void:
				target.set_entity_state("world:room:entity", {"persisted": true})
			)
			if not manager.quick_save():
				failures.append("quick save failed")
			elif not bool(storage.written.get_entity_state("world:room:entity").get("persisted", false)):
				failures.append("quick save wrote before runtime persistence listeners ran")
		manager.free()


	func _assert_resume_state_round_trip(failures: Array[String]) -> void:
		var snapshot: RefCounted = SAVE_SNAPSHOT.new()
		snapshot.slot = 1
		if not snapshot.has_method("set_resume_state"):
			failures.append("SaveSnapshot is missing set_resume_state")
			return
		if not snapshot.call("set_resume_state", Vector2(12, 34), Vector2(5, -6)):
			failures.append("SaveSnapshot rejected a finite resume transform")
		var codec: RefCounted = SAVE_CODEC.new()
		var decoded: RefCounted = codec.decode(codec.encode(snapshot), 1)
		if decoded == null:
			failures.append("resume state round trip lost the snapshot")
			return
		if decoded.get("has_resume") != true:
			failures.append("resume state flag did not round trip")
		if Vector2(decoded.get("resume_position")) != Vector2(12, 34):
			failures.append("resume position did not round trip")
		if Vector2(decoded.get("resume_velocity")) != Vector2(5, -6):
			failures.append("resume velocity did not round trip")
		decoded.call("clear_resume_state")
		if decoded.get("has_resume") == true or not (decoded.to_dictionary().get("player_resume", {}) as Dictionary).is_empty():
			failures.append("clear_resume_state left data behind")


	func _assert_invalid_resume_state_is_optional(failures: Array[String]) -> void:
		var snapshot: RefCounted = SAVE_SNAPSHOT.new()
		snapshot.slot = 1
		snapshot.world_id = "kept_world"
		var data: Dictionary = snapshot.to_dictionary()
		data["player_resume"] = {"position": {"x": "bad", "y": 0}, "velocity": {"x": 0, "y": 0}}
		var decoded: RefCounted = SAVE_CODEC.new().decode(JSON.stringify(data), 1)
		if decoded == null:
			failures.append("malformed optional resume data rejected the whole save")
		elif decoded.world_id != "kept_world" or decoded.get("has_resume") == true:
			failures.append("malformed optional resume data was not ignored")


## tests/save/test_save_storage.gd
class SaveStorageCase extends Node:
	const SAVE_SNAPSHOT: Script = preload("res://addons/platformer_kit/save/save_snapshot.gd")
	const SAVE_STORAGE: Script = preload("res://addons/platformer_kit/save/save_storage.gd")

	const TEST_ROOT := "user://wellwell_storage_test"


	func run() -> Array[String]:
		var failures: Array[String] = []
		_clear()
		_assert_write_and_read_slot(failures)
		_clear()
		_assert_backup_is_used_when_primary_is_invalid(failures)
		_clear()
		return failures


	func _assert_write_and_read_slot(failures: Array[String]) -> void:
		var storage: RefCounted = SAVE_STORAGE.new(TEST_ROOT)
		var snapshot: RefCounted = SAVE_SNAPSHOT.new()
		snapshot.slot = 1
		snapshot.respawn_position = Vector2(16, 24)
		snapshot.set_module_state(&"test_module", {"room": "level_01", "cell": "2,3"})

		if not storage.write_slot(snapshot):
			failures.append("write_slot returned false")
			return
		var loaded: RefCounted = storage.read_slot(1)
		if loaded == null:
			failures.append("read_slot returned null")
			return
		if loaded.respawn_position != Vector2(16, 24):
			failures.append("loaded respawn position was wrong")
		if loaded.get_module_state(&"test_module").get("cell", "") != "2,3":
			failures.append("loaded module state was missing")


	func _assert_backup_is_used_when_primary_is_invalid(failures: Array[String]) -> void:
		var storage: RefCounted = SAVE_STORAGE.new(TEST_ROOT)
		var snapshot: RefCounted = SAVE_SNAPSHOT.new()
		snapshot.slot = 1
		snapshot.set_module_state(&"test_module", {"source": "backup"})
		if not storage.write_slot(snapshot):
			failures.append("initial write failed")
			return

		var primary_path := "%s/slot_1.json" % TEST_ROOT
		var backup_path := "%s/slot_1.backup.json" % TEST_ROOT
		DirAccess.rename_absolute(
			ProjectSettings.globalize_path(primary_path),
			ProjectSettings.globalize_path(backup_path)
		)
		var file := FileAccess.open(primary_path, FileAccess.WRITE)
		file.store_string("{broken")
		file.close()

		var loaded: RefCounted = storage.read_slot(1)
		if loaded == null or loaded.get_module_state(&"test_module").get("source", "") != "backup":
			failures.append("backup snapshot was not loaded")


	func _clear() -> void:
		var storage: RefCounted = SAVE_STORAGE.new(TEST_ROOT)
		storage.delete_slot(1)
		var root := ProjectSettings.globalize_path(TEST_ROOT)
		if DirAccess.dir_exists_absolute(root):
			DirAccess.remove_absolute(root)


## tests/save/test_save_slots.gd
class SaveSlotsCase extends Node:
	const SAVE_SNAPSHOT := preload("res://addons/platformer_kit/save/save_snapshot.gd")
	const SAVE_MANAGER := preload("res://addons/platformer_kit/save/save_manager.gd")

	class EmptyStorage extends RefCounted:
		var write_count := 0
		var last_written: RefCounted

		func read_slot(_slot: int) -> RefCounted:
			return null

		func write_slot(snapshot: RefCounted) -> bool:
			write_count += 1
			last_written = snapshot
			return true

		func delete_slot(_slot: int) -> bool:
			return true

	func run() -> Array[String]:
		var failures: Array[String] = []
		_assert_manager_does_not_create_slot_on_ready(failures)
		_assert_prepare_slot_does_not_persist_or_select(failures)
		_assert_resume_api_uses_the_active_snapshot(failures)
		var source: RefCounted = SAVE_SNAPSHOT.new()
		source.slot = 1
		source.world_id = "world_01"
		source.current_room_id = "room_a"
		source.set_module_state(&"test_module", {"chunk": "world_01:chunk:0,0"})
		source.set_entity_state("world_01:room_a:switch", {"activated": true})
		var restored: RefCounted = SAVE_SNAPSHOT.from_dictionary(source.to_dictionary())
		if restored == null:
			failures.append("extended save snapshot could not decode")
			return failures
		if restored.world_id != "world_01" or restored.current_room_id != "room_a":
			failures.append("room progress did not round trip")
		if restored.get_module_state(&"test_module").get("chunk", "") != "world_01:chunk:0,0":
			failures.append("module state did not round trip")
		if not bool(restored.get_entity_state("world_01:room_a:switch").get("activated", false)):
			failures.append("entity state did not round trip")
		return failures


	func _assert_prepare_slot_does_not_persist_or_select(failures: Array[String]) -> void:
		var storage := EmptyStorage.new()
		var manager: Node = SAVE_MANAGER.new()
		manager.setup_storage(storage)
		if not manager.has_method("prepare_slot") or not manager.has_method("activate_snapshot"):
			failures.append("save manager is missing transactional slot startup APIs")
			manager.free()
			return
		var snapshot: RefCounted = manager.call("prepare_slot", 2)
		if snapshot == null or snapshot.slot != 2:
			failures.append("prepare_slot did not create an in-memory snapshot")
		if storage.write_count != 0 or manager.selected_slot != 0 or manager.current_snapshot != null:
			failures.append("prepare_slot persisted or selected a slot before world readiness")
		if not manager.call("activate_snapshot", snapshot):
			failures.append("activate_snapshot rejected the prepared snapshot")
		if storage.write_count != 1 or manager.selected_slot != 2 or manager.current_snapshot != snapshot:
			failures.append("activate_snapshot did not persist and select the ready slot")
		manager.free()

	func _assert_manager_does_not_create_slot_on_ready(failures: Array[String]) -> void:
		var storage := EmptyStorage.new()
		var manager: Node = SAVE_MANAGER.new()
		manager.setup_storage(storage)
		manager.call("_ready")
		if storage.write_count != 0:
			failures.append("save manager created a slot before the player selected one")
		manager.free()


	func _assert_resume_api_uses_the_active_snapshot(failures: Array[String]) -> void:
		var storage := EmptyStorage.new()
		var manager: Node = SAVE_MANAGER.new()
		manager.setup_storage(storage)
		if manager.call("set_resume_state", Vector2(1, 2), Vector2(3, 4), true):
			failures.append("save manager accepted resume data without an active snapshot")
		var snapshot: RefCounted = SAVE_SNAPSHOT.new()
		snapshot.slot = 1
		manager.current_snapshot = snapshot
		if not manager.call("set_resume_state", Vector2(4, 8), Vector2(1, 0), true):
			failures.append("save manager rejected valid resume data")
		if snapshot.has_resume != true or snapshot.resume_position != Vector2(4, 8) or snapshot.resume_velocity != Vector2(1, 0):
			failures.append("save manager did not write resume data to the active snapshot")
		if storage.write_count != 1 or storage.last_written != snapshot:
			failures.append("immediate resume write did not commit the active snapshot")
		if not manager.call("clear_resume_state", true):
			failures.append("save manager rejected clearing resume data")
		if snapshot.has_resume or storage.write_count != 2:
			failures.append("clearing resume data did not persist the change")
		manager.free()


## tests/save/test_realtime_save.gd
class RealtimeSaveCase extends Node:
	const SERVICE_PATH := "res://game/save/realtime_save_service.gd"
	const SAVE_SNAPSHOT := preload("res://addons/platformer_kit/save/save_snapshot.gd")


	class FakePlayer extends CharacterBody2D:
		pass


	class FakeSettings extends Node:
		signal settings_changed

		var enabled := true

		func is_realtime_save_enabled() -> bool:
			return enabled

		func set_enabled(value: bool) -> void:
			enabled = value
			settings_changed.emit()


	class FakeSession extends Node:
		signal world_ready
		signal world_start_failed(errors: Array[String])

		var _active_snapshot: RefCounted


	class FakeManager extends Node:
		var current_snapshot: RefCounted = SAVE_SNAPSHOT.new()
		var set_calls := 0
		var clear_calls := 0
		var last_position := Vector2.ZERO
		var last_velocity := Vector2.ZERO
		var last_immediate := false

		func set_resume_state(position: Vector2, velocity: Vector2, immediate := false) -> bool:
			set_calls += 1
			last_position = position
			last_velocity = velocity
			last_immediate = immediate
			return current_snapshot.set_resume_state(position, velocity)

		func clear_resume_state(immediate := false) -> bool:
			clear_calls += 1
			last_immediate = immediate
			current_snapshot.clear_resume_state()
			return true


	func run() -> Array[String]:
		var failures: Array[String] = []
		var script := load(SERVICE_PATH) as Script
		if script == null or not script.can_instantiate():
			return ["realtime save service is missing: %s" % SERVICE_PATH]
		var service: Node = script.new() as Node
		if service == null:
			return ["realtime save service could not be instantiated"]
		add_child(service)
		var player := FakePlayer.new()
		player.name = "FakePlayer"
		add_child(player)
		var manager := FakeManager.new()
		manager.name = "FakeManager"
		add_child(manager)
		var settings := FakeSettings.new()
		settings.name = "FakeSettings"
		add_child(settings)
		if not service.has_method("bind_sources"):
			failures.append("realtime save service is missing bind_sources")
			_cleanup(service, player, manager, settings)
			return failures
		service.call("bind_sources", player, manager, settings)

		player.global_position = Vector2(64, 32)
		player.velocity = Vector2(10, -2)
		service.call("set_active", true)
		if manager.set_calls != 1:
			failures.append("world activation did not capture the live transform")
		if manager.last_position != Vector2(64, 32) or manager.last_velocity != Vector2(10, -2):
			failures.append("realtime save captured the wrong transform")

		if bool(service.call("capture_now")):
			failures.append("realtime save rewrote an unchanged transform")
		if manager.set_calls != 1:
			failures.append("unchanged transform still reached the save manager")

		player.global_position = Vector2(80, 40)
		if not bool(service.call("capture_now")):
			failures.append("realtime save ignored a moved player")
		if manager.last_position != Vector2(80, 40):
			failures.append("realtime save did not update the moved position")

		settings.set_enabled(false)
		if manager.clear_calls != 1:
			failures.append("disabling realtime save did not clear resume data")
		if bool(manager.current_snapshot.get("has_resume")):
			failures.append("disabling realtime save left resume data behind")
		if bool(service.call("capture_now")):
			failures.append("realtime save kept capturing after being disabled")

		settings.set_enabled(true)
		if manager.set_calls != 3:
			failures.append("realtime save did not resume after being re-enabled")
		var before_flush := manager.set_calls
		if not bool(service.call("flush")):
			failures.append("realtime save flush failed")
		if manager.set_calls != before_flush + 1 or not manager.last_immediate:
			failures.append("flush did not force an immediate save")

		service.call("set_active", false)
		if bool(service.call("capture_now")):
			failures.append("realtime save captured while the session was inactive")

		var session := FakeSession.new()
		add_child(session)
		var stale_snapshot: RefCounted = SAVE_SNAPSHOT.new()
		session._active_snapshot = SAVE_SNAPSHOT.new()
		manager.current_snapshot = stale_snapshot
		service.call("bind_sources", player, manager, settings, session)
		service.call("set_active", true)
		var stale_writes := manager.set_calls
		player.global_position = Vector2(120, 64)
		if bool(service.call("capture_now")):
			failures.append("realtime save wrote into a snapshot that was not active")
		if manager.set_calls != stale_writes:
			failures.append("stale snapshot guard still reached the save manager")
		manager.current_snapshot = session._active_snapshot
		if not bool(service.call("capture_now")):
			failures.append("realtime save did not capture after the slot became active")

		_cleanup(service, player, manager, settings)
		session.free()
		return failures


	func _cleanup(service: Node, player: Node, manager: Node, settings: Node) -> void:
		service.free()
		player.free()
		manager.free()
		settings.free()


## tests/save/test_realtime_save_integration.gd
class RealtimeSaveIntegrationCase extends Node:
	const WORLD_ROOT := preload("res://scenes/runtime/world_root.tscn")
	const SAVE_SNAPSHOT := preload("res://addons/platformer_kit/save/save_snapshot.gd")


	class FakeSettings extends Node:
		var enabled := true

		func is_realtime_save_enabled() -> bool:
			return enabled


	class FakeManager extends Node:
		var current_snapshot: RefCounted

		func set_resume_state(position: Vector2, velocity: Vector2, _immediate := false) -> bool:
			return current_snapshot != null and current_snapshot.set_resume_state(position, velocity)

		func clear_resume_state(_immediate := false) -> bool:
			if current_snapshot == null:
				return false
			current_snapshot.clear_resume_state()
			return true


	func run() -> Array[String]:
		var failures: Array[String] = []
		var root := WORLD_ROOT.instantiate() as Node2D
		add_child(root)
		var service := root.get_node_or_null("RealtimeSave")
		if service == null:
			failures.append("world_root is missing the realtime save service")
			root.free()
			return failures
		var snapshot: RefCounted = SAVE_SNAPSHOT.new()
		snapshot.slot = 1
		var manager := FakeManager.new()
		manager.current_snapshot = snapshot
		add_child(manager)
		var settings := FakeSettings.new()
		add_child(settings)
		var player := root.get_node("Player") as Node2D
		service.call("bind_sources", player, manager, settings, root)
		if not bool(root.call("start_selected_snapshot", snapshot)):
			failures.append("world root could not start the realtime resume fixture")
			_cleanup(root, manager, settings)
			return failures

		var world: Resource = root.get("world_data")
		var runtime := root.get_node("WorldRuntime")
		var room_id := String(runtime.call("get_current_room_id"))
		var room_rect: Rect2i = world.call("get_room_pixel_rect", room_id)
		var target := Vector2(room_rect.position) + Vector2(room_rect.size) * 0.5
		var target_velocity := Vector2(12, -4)
		player.global_position = target
		player.set("velocity", target_velocity)
		if not bool(service.call("flush")):
			failures.append("realtime save flush did not record the live transform")
			_cleanup(root, manager, settings)
			return failures
		if not snapshot.has_resume:
			failures.append("realtime save flush left the snapshot without resume data")
			_cleanup(root, manager, settings)
			return failures

		root.call("stop")
		if not bool(root.call("start_selected_snapshot", snapshot)):
			failures.append("world root could not restart from the realtime snapshot")
		elif player.global_position != target:
			failures.append("world root did not resume the exact player position")
		elif Vector2(player.get("velocity")) != target_velocity:
			failures.append("world root did not resume the saved velocity")

		_cleanup(root, manager, settings)
		return failures


	func _cleanup(root: Node, manager: Node, settings: Node) -> void:
		root.call("stop")
		root.free()
		manager.free()
		settings.free()


func run() -> Array[String]:
	var failures: Array[String] = []
	failures.append_array(_run_case(SaveCodecCase.new()))
	failures.append_array(_run_case(SaveStorageCase.new()))
	failures.append_array(_run_case(SaveSlotsCase.new()))
	failures.append_array(_run_case(RealtimeSaveCase.new()))
	failures.append_array(_run_case(RealtimeSaveIntegrationCase.new()))
	return failures


func _run_case(test: Node) -> Array[String]:
	add_child(test)
	var result: Array = test.call("run")
	test.queue_free()
	var failures: Array[String] = []
	failures.assign(result)
	return failures
