extends Node


class FailingRoomBaker extends "res://scripts/authoring/room_baker.gd":
	var promote_attempts := 0

	func _promote_staged_file(staged_path: String, final_path: String) -> Error:
		promote_attempts += 1
		if promote_attempts == 2:
			return ERR_CANT_CREATE
		return super._promote_staged_file(staged_path, final_path)


class WarningRoomBaker extends "res://scripts/authoring/room_baker.gd":
	func validate(_source_root: Node) -> Dictionary:
		return {"ok": true, "errors": [], "warnings": ["test authoring warning"]}


class RemovalFailingRoomBaker extends "res://scripts/authoring/room_baker.gd":
	var promote_attempts := 0
	var fail_removal_path := ""

	func _promote_staged_file(staged_path: String, final_path: String) -> Error:
		promote_attempts += 1
		if promote_attempts == 2:
			return ERR_CANT_CREATE
		return super._promote_staged_file(staged_path, final_path)

	func _remove_file(path: String) -> Error:
		if path == fail_removal_path:
			return ERR_CANT_CREATE
		return super._remove_file(path)


class PostSaveMutationBaker extends "res://scripts/authoring/room_baker.gd":
	var mutation := ""

	func _after_staged_resources_saved(staged_paths: Dictionary, _staged: Dictionary) -> Dictionary:
		if mutation == "missing nested descendant":
			var scene := ResourceLoader.load(staged_paths["runtime_scene_path"], "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
			var root: Node = scene.instantiate()
			var child: Node = root.get_node_or_null("CreatorNode/CreatorChild")
			child.get_parent().remove_child(child)
			child.free()
			ResourceSaver.save(_pack_scene_root(root), staged_paths["runtime_scene_path"])
			root.free()
		elif mutation == "injected preview":
			var scene := ResourceLoader.load(staged_paths["runtime_scene_path"], "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
			var root: Node = scene.instantiate()
			var preview := Node2D.new()
			preview.name = "PreviewOnly"
			root.add_child(preview)
			preview.owner = root
			ResourceSaver.save(_pack_scene_root(root), staged_paths["runtime_scene_path"])
			root.free()
		elif mutation == "metadata corruption":
			var room_data := ResourceLoader.load(staged_paths["room_resource_path"], "RoomData", ResourceLoader.CACHE_MODE_IGNORE) as Resource
			room_data.display_name = "Post Save Corruption"
			ResourceSaver.save(room_data, staged_paths["room_resource_path"])
		return {"ok": true, "errors": [], "warnings": []}

	func _pack_scene_root(root: Node) -> PackedScene:
		for child: Node in root.get_children():
			_assign_owner_recursive(child, root)
		var scene := PackedScene.new()
		scene.pack(root)
		return scene

	func _assign_owner_recursive(node: Node, root: Node) -> void:
		node.owner = root
		for child: Node in node.get_children():
			_assign_owner_recursive(child, root)


class BackupCleanupFailingRoomBaker extends "res://scripts/authoring/room_baker.gd":
	var failing_backup_path := ""

	func _remove_file(path: String) -> Error:
		if path == failing_backup_path:
			return ERR_CANT_CREATE
		return super._remove_file(path)


class CanonicalizationInspectingRoomBaker extends "res://scripts/authoring/room_baker.gd":
	func canonicalize(value: Variant) -> Variant:
		return _canonicalize_value(value)


class UIDRegisteringRoomBaker extends "res://scripts/authoring/room_baker.gd":
	var registered_ids: Array[int] = []
	var final_paths_by_uid: Dictionary = {}

	func _after_staged_resources_saved(staged_paths: Dictionary, _staged: Dictionary) -> Dictionary:
		for staged_path: String in staged_paths.values():
			var uid := ResourceUID.create_id()
			if ResourceSaver.set_uid(staged_path, uid) != OK:
				return {"ok": false, "errors": ["could not assign staged test UID"], "warnings": []}
			ResourceUID.add_id(uid, staged_path)
			registered_ids.append(uid)
			final_paths_by_uid[uid] = staged_path.replace(".stage.", ".")
		return {"ok": true, "errors": [], "warnings": []}


const ROOM_BAKER: Script = preload("res://scripts/authoring/room_baker.gd")
const ROOM_BAKE_PATHS: Script = preload("res://scripts/authoring/room_bake_paths.gd")
const ROOM_DATA: Script = preload("res://scripts/world/room_data.gd")
const ROOM_AUTHORING_ROOT: Script = preload("res://scripts/authoring/room_authoring_root.gd")
const ROOM_ENTRANCE: Script = preload("res://scripts/world/room_entrance.gd")
const SPAWN_POINT: Script = preload("res://scripts/world/spawn_point.gd")
const WORLD_ENTITY: Script = preload("res://scripts/world/world_entity.gd")
const EMBEDDED_SIGNATURE_RESOURCE: Script = preload("res://tests/authoring/embedded_signature_resource_fixture.gd")
const SIGNATURE_FIXTURE_NODE: Script = preload("res://tests/authoring/signature_fixture_node.gd")

const ROOM_ID := "test_room_baker_case"
const SOURCE_PATH := "res://tests/authoring/test_room_baker_source.tscn"


func run() -> Array[String]:
	var failures: Array[String] = []
	var paths: Dictionary = ROOM_BAKE_PATHS.for_room_id(ROOM_ID)
	_cleanup(paths)

	var source: Node = _make_source()
	var baker: RefCounted = ROOM_BAKER.new()
	var validation: Dictionary = baker.validate(source)
	_assert_result_envelope(validation, "validate", failures)
	if not validation.get("ok", false):
		failures.append("valid authoring source did not validate: %s" % validation.get("errors", []))
	if _any_output_exists(paths):
		failures.append("validation wrote generated output files")

	var staged: Dictionary = baker.stage(source, SOURCE_PATH)
	_assert_result_envelope(staged, "stage", failures)
	if not staged.get("ok", false):
		failures.append("valid authoring source did not stage: %s" % staged.get("errors", []))
	if _any_output_exists(paths):
		failures.append("staging wrote generated output files")

	var first_bake: Dictionary = baker.bake(source, SOURCE_PATH)
	_assert_result_envelope(first_bake, "bake", failures)
	if not first_bake.get("ok", false):
		failures.append("valid authoring source did not bake: %s" % first_bake.get("errors", []))
	var first_contract := _load_contract(paths, failures)
	_assert_split_contract(first_contract, paths, failures)
	_assert_room_metadata(first_contract, paths, failures)
	_assert_promoted_resource_uids_resolve_to_final_paths(source, paths, failures)
	_assert_no_temporary_outputs(paths, failures)
	_assert_malformed_staged_barriers(baker, source, paths, failures)
	_assert_signature_property_barriers(baker, source, paths, failures)
	_assert_embedded_resource_and_dictionary_signatures(baker, source, paths, failures)
	_assert_post_save_reload_barriers(baker, source, paths, failures)
	_assert_committed_backup_cleanup_warning(baker, source, paths, failures)
	_assert_warning_propagation(source, paths, failures)

	var second_bake: Dictionary = baker.bake(source, SOURCE_PATH)
	_assert_result_envelope(second_bake, "second bake", failures)
	if not second_bake.get("ok", false):
		failures.append("unchanged authoring source did not bake a second time: %s" % second_bake.get("errors", []))
	var second_contract := _load_contract(paths, failures)
	if first_contract != second_contract:
		failures.append("unchanged source produced a different loaded bake contract")

	source.room_id = ""
	var invalid_bake: Dictionary = baker.bake(source, SOURCE_PATH)
	_assert_result_envelope(invalid_bake, "invalid bake", failures)
	if invalid_bake.get("ok", false):
		failures.append("invalid authoring source was baked")
	var after_invalid_contract := _load_contract(paths, failures)
	if second_contract != after_invalid_contract:
		failures.append("failed validation changed the previous generated outputs")
	source.room_id = ROOM_ID

	source.display_name = "Should Not Replace"
	var failing_baker: RefCounted = FailingRoomBaker.new()
	var failed_replacement: Dictionary = failing_baker.bake(source, SOURCE_PATH)
	_assert_result_envelope(failed_replacement, "replacement failure", failures)
	if failed_replacement.get("ok", false):
		failures.append("forced replacement failure was reported as success")
	var after_rollback_contract := _load_contract(paths, failures)
	if second_contract != after_rollback_contract:
		failures.append("forced replacement failure did not restore the previous complete outputs")
	_assert_no_temporary_outputs(paths, failures)
	_assert_rollback_without_existing_outputs(source, paths, failures)
	_assert_rollback_with_subset_outputs(source, baker, paths, failures)
	_assert_removal_failure_preserves_backup_evidence(source, baker, paths, failures)

	source.free()
	_cleanup(paths)
	if _any_output_exists(paths):
		failures.append("test cleanup left generated room baker output files")
	return failures


func _assert_signature_property_barriers(baker: RefCounted, source: Node, paths: Dictionary, failures: Array[String]) -> void:
	var cases: Array[Dictionary] = [
		{"label": "changed Node2D transform", "builder": Callable(self, "_stage_with_changed_transform")},
		{"label": "changed exported property", "builder": Callable(self, "_stage_with_changed_exported_property")},
		{"label": "removed persistent group", "builder": Callable(self, "_stage_without_persistent_group")},
	]
	for test_case: Dictionary in cases:
		var restore: Dictionary = baker.bake(source, SOURCE_PATH)
		if not restore.get("ok", false):
			failures.append("could not establish finals before signature case: %s" % test_case["label"])
			continue
		var before_contract := _load_contract(paths, failures)
		var staged: Dictionary = test_case["builder"].call(baker, source)
		var result: Dictionary = baker.save_staged(staged)
		_assert_result_envelope(result, "signature case %s" % test_case["label"], failures)
		if result.get("ok", false):
			failures.append("scene signature accepted %s" % test_case["label"])
		if before_contract != _load_contract(paths, failures):
			failures.append("scene signature failure changed finals: %s" % test_case["label"])
		_assert_no_temporary_outputs(paths, failures)


func _assert_embedded_resource_and_dictionary_signatures(baker: RefCounted, source: Node, paths: Dictionary, failures: Array[String]) -> void:
	_assert_textual_variant_key_identity(failures)
	var cycle_source: Node = _make_source(true, true)
	var cycle_stage: Dictionary = baker.stage(cycle_source, SOURCE_PATH)
	_assert_result_envelope(cycle_stage, "cyclic embedded resource stage", failures)
	if not cycle_stage.get("ok", false):
		failures.append("cyclic embedded Resource could not be canonicalized")
	_clear_staged_embedded_cycle(cycle_stage)
	cycle_source.free()
	var fixture_source: Node = _make_source(true)
	for test_case: Dictionary in [
		{"label": "later embedded Resource property", "builder": Callable(self, "_stage_with_changed_embedded_resource_property")},
		{"label": "embedded Resource resource_name", "builder": Callable(self, "_stage_with_changed_embedded_resource_name")},
		{"label": "non-string dictionary key", "builder": Callable(self, "_stage_with_changed_integer_dictionary_key")},
	]:
		var restore: Dictionary = baker.bake(fixture_source, SOURCE_PATH)
		if not restore.get("ok", false):
			failures.append("could not establish finals before canonicalization case: %s (%s)" % [test_case["label"], restore.get("errors", [])])
			continue
		var before_contract := _load_contract(paths, failures)
		var staged: Dictionary = test_case["builder"].call(baker, fixture_source)
		var result: Dictionary = baker.save_staged(staged)
		_assert_result_envelope(result, "canonicalization case %s" % test_case["label"], failures)
		if result.get("ok", false):
			failures.append("scene signature accepted changed %s" % test_case["label"])
		if before_contract != _load_contract(paths, failures):
			failures.append("canonicalization failure changed finals: %s" % test_case["label"])
		_assert_no_temporary_outputs(paths, failures)
	fixture_source.free()


func _assert_textual_variant_key_identity(failures: Array[String]) -> void:
	var inspector := CanonicalizationInspectingRoomBaker.new()
	var canonical_keys: Dictionary = {}
	canonical_keys[inspector.canonicalize("shared")] = "String"
	canonical_keys[inspector.canonicalize(StringName("shared"))] = "StringName"
	canonical_keys[inspector.canonicalize(NodePath("shared"))] = "NodePath"
	if canonical_keys.size() != 3:
		failures.append("canonicalization collided textually equivalent String/StringName/NodePath dictionary keys")
		return
	if canonical_keys.get("shared") != "String":
		failures.append("canonicalization did not retain String dictionary key identity")
	if canonical_keys.get({"variant_type": "StringName", "value": "shared"}) != "StringName":
		failures.append("canonicalization did not retain StringName dictionary key identity")
	if canonical_keys.get({"variant_type": "NodePath", "value": "shared"}) != "NodePath":
		failures.append("canonicalization did not retain String/StringName/NodePath dictionary key identity")


func _assert_promoted_resource_uids_resolve_to_final_paths(source: Node, paths: Dictionary, failures: Array[String]) -> void:
	var stale_stage_path := _marked_path(paths["room_resource_path"], ".stage")
	var stale_uid := ResourceUID.create_id()
	ResourceUID.add_id(stale_uid, stale_stage_path)
	var uid_baker := UIDRegisteringRoomBaker.new()
	var result: Dictionary = uid_baker.bake(source, SOURCE_PATH)
	if not result.get("ok", false):
		failures.append("could not bake UID promotion fixture: %s" % result.get("errors", []))
	if ResourceUID.has_id(stale_uid):
		failures.append("stale staged resource UID was retained after a new bake")
	for uid: int in uid_baker.registered_ids:
		var final_path := String(uid_baker.final_paths_by_uid[uid])
		if ResourceUID.get_id_path(uid) != final_path:
			failures.append(
				"promoted resource UID resolves to %s instead of %s"
				% [ResourceUID.get_id_path(uid), final_path]
			)
	for uid: int in uid_baker.registered_ids:
		if ResourceUID.has_id(uid):
			ResourceUID.remove_id(uid)
	if ResourceUID.has_id(stale_uid):
		ResourceUID.remove_id(stale_uid)


func _stage_with_changed_embedded_resource_property(baker: RefCounted, source: Node) -> Dictionary:
	var staged: Dictionary = baker.stage(source, SOURCE_PATH)
	var root: Node = (staged["runtime_scene"] as PackedScene).instantiate()
	var node: Node = root.get_node("CreatorNode")
	var resource: Resource = node.get("embedded_resource") as Resource
	resource.set("later_value", "changed later value")
	staged["runtime_scene"] = _pack_scene_root(root)
	root.free()
	return staged


func _stage_with_changed_embedded_resource_name(baker: RefCounted, source: Node) -> Dictionary:
	var staged: Dictionary = baker.stage(source, SOURCE_PATH)
	var root: Node = (staged["runtime_scene"] as PackedScene).instantiate()
	var node: Node = root.get_node("CreatorNode")
	var resource: Resource = node.get("embedded_resource") as Resource
	resource.resource_name = "changed_embedded_signature"
	staged["runtime_scene"] = _pack_scene_root(root)
	root.free()
	return staged


func _stage_with_changed_integer_dictionary_key(baker: RefCounted, source: Node) -> Dictionary:
	var staged: Dictionary = baker.stage(source, SOURCE_PATH)
	var root: Node = (staged["runtime_scene"] as PackedScene).instantiate()
	var node: Node = root.get_node("CreatorNode")
	var values: Dictionary = node.get("mixed_values")
	values[1] = "changed integer key"
	node.set("mixed_values", values)
	staged["runtime_scene"] = _pack_scene_root(root)
	root.free()
	return staged


func _clear_staged_embedded_cycle(staged: Dictionary) -> void:
	var scene := staged.get("runtime_scene") as PackedScene
	if scene == null:
		return
	var root: Node = scene.instantiate()
	var node: Node = root.get_node_or_null("CreatorNode")
	if node != null:
		var resource: Resource = node.get("embedded_resource") as Resource
		if resource != null:
			resource.set("cyclic_resource", null)
	root.free()
	staged["runtime_scene"] = null
	staged["terrain_scene"] = null
	staged["room_data"] = null


func _assert_post_save_reload_barriers(baker: RefCounted, source: Node, paths: Dictionary, failures: Array[String]) -> void:
	for mutation: String in ["missing nested descendant", "injected preview", "metadata corruption"]:
		var restore: Dictionary = baker.bake(source, SOURCE_PATH)
		if not restore.get("ok", false):
			failures.append("could not establish finals before post-save case: %s" % mutation)
			continue
		var before_contract := _load_contract(paths, failures)
		var mutating_baker: PostSaveMutationBaker = PostSaveMutationBaker.new()
		mutating_baker.mutation = mutation
		var result: Dictionary = mutating_baker.bake(source, SOURCE_PATH)
		_assert_result_envelope(result, "post-save mutation %s" % mutation, failures)
		if result.get("ok", false):
			failures.append("post-save reload validation accepted %s" % mutation)
		if before_contract != _load_contract(paths, failures):
			failures.append("post-save reload validation changed finals: %s" % mutation)
		_assert_no_temporary_outputs(paths, failures)


func _assert_committed_backup_cleanup_warning(baker: RefCounted, source: Node, paths: Dictionary, failures: Array[String]) -> void:
	var baseline: Dictionary = baker.bake(source, SOURCE_PATH)
	if not baseline.get("ok", false):
		failures.append("could not establish committed cleanup baseline")
		return
	source.display_name = "Committed Backup Cleanup"
	var cleanup_baker: BackupCleanupFailingRoomBaker = BackupCleanupFailingRoomBaker.new()
	cleanup_baker.failing_backup_path = _marked_path(paths["runtime_scene_path"], ".backup")
	var result: Dictionary = cleanup_baker.bake(source, SOURCE_PATH)
	_assert_result_envelope(result, "committed backup cleanup", failures)
	if not result.get("ok", false):
		failures.append("committed transaction was reported as failed after backup cleanup error")
	if result.get("errors", []) != []:
		failures.append("committed transaction returned errors after backup cleanup error")
	if not _contains_warning(result, "retained generated output backup"):
		failures.append("committed transaction did not report retained backup warning")
	var contract := _load_contract(paths, failures)
	if contract.get("display_name") != "Committed Backup Cleanup":
		failures.append("committed transaction did not retain new finals after backup cleanup error")
	if not FileAccess.file_exists(cleanup_baker.failing_backup_path):
		failures.append("committed transaction did not retain the failed backup file")
	for backup_path: String in [_marked_path(paths["terrain_scene_path"], ".backup"), _marked_path(paths["room_resource_path"], ".backup")]:
		if FileAccess.file_exists(backup_path):
			failures.append("committed transaction did not continue safe backup cleanup: %s" % backup_path)
	source.display_name = "Room Baker Test"
	_cleanup(paths)


func _stage_with_changed_transform(baker: RefCounted, source: Node) -> Dictionary:
	var staged: Dictionary = baker.stage(source, SOURCE_PATH)
	var root: Node = (staged["runtime_scene"] as PackedScene).instantiate()
	var node: Node2D = root.get_node("Entities/PersistentSwitch") as Node2D
	node.position = Vector2(101.0, 103.0)
	staged["runtime_scene"] = _pack_scene_root(root)
	root.free()
	return staged


func _stage_with_changed_exported_property(baker: RefCounted, source: Node) -> Dictionary:
	var staged: Dictionary = baker.stage(source, SOURCE_PATH)
	var root: Node = (staged["runtime_scene"] as PackedScene).instantiate()
	var node: Node = root.get_node("Entities/PersistentSwitch")
	node.set("entity_id", "changed_exported_id")
	staged["runtime_scene"] = _pack_scene_root(root)
	root.free()
	return staged


func _stage_without_persistent_group(baker: RefCounted, source: Node) -> Dictionary:
	var staged: Dictionary = baker.stage(source, SOURCE_PATH)
	var root: Node = (staged["runtime_scene"] as PackedScene).instantiate()
	var node: Node = root.get_node("Entities/PersistentSwitch")
	node.remove_from_group("room_baker_runtime_group")
	staged["runtime_scene"] = _pack_scene_root(root)
	root.free()
	return staged


func _assert_malformed_staged_barriers(baker: RefCounted, source: Node, paths: Dictionary, failures: Array[String]) -> void:
	var cases: Array[Dictionary] = [
		{"label": "missing terrain child", "builder": Callable(self, "_stage_without_terrain_child")},
		{"label": "missing terrain layer", "builder": Callable(self, "_stage_without_terrain_layer")},
		{"label": "missing arbitrary runtime descendant", "builder": Callable(self, "_stage_without_creator_descendant")},
		{"label": "runtime PreviewOnly injection", "builder": Callable(self, "_stage_with_runtime_preview")},
		{"label": "altered RoomData metadata", "builder": Callable(self, "_stage_with_altered_metadata")},
	]
	for test_case: Dictionary in cases:
		var restore_result: Dictionary = baker.bake(source, SOURCE_PATH)
		_assert_result_envelope(restore_result, "restore before %s" % test_case["label"], failures)
		if not restore_result.get("ok", false):
			failures.append("could not establish finals before malformed staged case: %s" % test_case["label"])
			continue
		var before_contract := _load_contract(paths, failures)
		var malformed: Dictionary = test_case["builder"].call(baker, source)
		_assert_result_envelope(malformed, "malformed stage %s" % test_case["label"], failures)
		if not malformed.get("ok", false):
			failures.append("malformed staging setup failed unexpectedly: %s" % test_case["label"])
			continue
		var save_result: Dictionary = baker.save_staged(malformed)
		_assert_result_envelope(save_result, "malformed save %s" % test_case["label"], failures)
		if save_result.get("ok", false):
			failures.append("validation barrier accepted malformed staged resource: %s" % test_case["label"])
		var after_contract := _load_contract(paths, failures)
		if before_contract != after_contract:
			failures.append("validation barrier changed previous finals: %s" % test_case["label"])
		_assert_no_temporary_outputs(paths, failures)


func _assert_warning_propagation(source: Node, paths: Dictionary, failures: Array[String]) -> void:
	var warning_baker: RefCounted = WarningRoomBaker.new()
	var warning_staged: Dictionary = warning_baker.stage(source, SOURCE_PATH)
	_assert_result_envelope(warning_staged, "warning stage", failures)
	_assert_warnings(warning_staged, "warning stage", failures)
	var warning_save: Dictionary = warning_baker.save_staged(warning_staged)
	_assert_result_envelope(warning_save, "warning save", failures)
	_assert_warnings(warning_save, "warning save", failures)
	var warning_bake: Dictionary = warning_baker.bake(source, SOURCE_PATH)
	_assert_result_envelope(warning_bake, "warning bake", failures)
	_assert_warnings(warning_bake, "warning bake", failures)
	_assert_no_temporary_outputs(paths, failures)


func _assert_rollback_without_existing_outputs(source: Node, paths: Dictionary, failures: Array[String]) -> void:
	_remove_final_outputs(paths)
	var failing_baker: RefCounted = FailingRoomBaker.new()
	var result: Dictionary = failing_baker.bake(source, SOURCE_PATH)
	_assert_result_envelope(result, "rollback without finals", failures)
	if result.get("ok", false):
		failures.append("replacement failure without finals was reported as success")
	for final_path: String in _final_paths(paths):
		if FileAccess.file_exists(final_path):
			failures.append("rollback without finals left a newly installed file: %s" % final_path)
	_assert_no_temporary_outputs(paths, failures)


func _assert_rollback_with_subset_outputs(source: Node, baker: RefCounted, paths: Dictionary, failures: Array[String]) -> void:
	var baseline: Dictionary = baker.bake(source, SOURCE_PATH)
	_assert_result_envelope(baseline, "subset rollback baseline", failures)
	if not baseline.get("ok", false):
		failures.append("could not establish subset rollback baseline")
		return
	var missing_path: String = paths["terrain_scene_path"]
	DirAccess.remove_absolute(ProjectSettings.globalize_path(missing_path))
	var failing_baker: RefCounted = FailingRoomBaker.new()
	var result: Dictionary = failing_baker.bake(source, SOURCE_PATH)
	_assert_result_envelope(result, "rollback with subset finals", failures)
	if result.get("ok", false):
		failures.append("replacement failure with subset finals was reported as success")
	for final_path: String in [paths["runtime_scene_path"], paths["room_resource_path"]]:
		if not FileAccess.file_exists(final_path):
			failures.append("rollback with subset finals did not restore: %s" % final_path)
	if FileAccess.file_exists(missing_path):
		failures.append("rollback with subset finals left a newly installed terrain file")
	_assert_no_temporary_outputs(paths, failures)


func _assert_removal_failure_preserves_backup_evidence(source: Node, baker: RefCounted, paths: Dictionary, failures: Array[String]) -> void:
	var baseline: Dictionary = baker.bake(source, SOURCE_PATH)
	_assert_result_envelope(baseline, "removal failure baseline", failures)
	if not baseline.get("ok", false):
		failures.append("could not establish removal failure baseline")
		return
	source.display_name = "Removal Failure"
	var failing_baker: RemovalFailingRoomBaker = RemovalFailingRoomBaker.new()
	failing_baker.fail_removal_path = paths["runtime_scene_path"]
	var result: Dictionary = failing_baker.bake(source, SOURCE_PATH)
	_assert_result_envelope(result, "removal failure rollback", failures)
	if result.get("ok", false):
		failures.append("forced removal failure was reported as success")
	if not _contains_error(result, "could not remove newly installed output"):
		failures.append("forced removal failure was not reported")
	var backup_path := _marked_path(paths["runtime_scene_path"], ".backup")
	if not FileAccess.file_exists(backup_path):
		failures.append("forced removal failure silently removed backup evidence")
	source.display_name = "Room Baker Test"
	_cleanup(paths)


func _stage_without_terrain_child(baker: RefCounted, source: Node) -> Dictionary:
	var staged: Dictionary = baker.stage(source, SOURCE_PATH)
	var root: Node = (staged["terrain_scene"] as PackedScene).instantiate()
	var background: Node = root.get_node_or_null("Background")
	if background != null:
		root.remove_child(background)
		background.free()
	staged["terrain_scene"] = _pack_scene_root(root)
	root.free()
	return staged


func _stage_without_terrain_layer(baker: RefCounted, source: Node) -> Dictionary:
	var staged: Dictionary = baker.stage(source, SOURCE_PATH)
	var root: Node = (staged["terrain_scene"] as PackedScene).instantiate()
	var layer: Node = root.get_node_or_null("Terrain/BackTiles")
	if layer != null:
		layer.get_parent().remove_child(layer)
		layer.free()
	staged["terrain_scene"] = _pack_scene_root(root)
	root.free()
	return staged


func _stage_without_creator_descendant(baker: RefCounted, source: Node) -> Dictionary:
	var staged: Dictionary = baker.stage(source, SOURCE_PATH)
	var root: Node = (staged["runtime_scene"] as PackedScene).instantiate()
	var creator_child: Node = root.get_node_or_null("CreatorNode/CreatorChild")
	if creator_child != null:
		creator_child.get_parent().remove_child(creator_child)
		creator_child.free()
	staged["runtime_scene"] = _pack_scene_root(root)
	root.free()
	return staged


func _stage_with_runtime_preview(baker: RefCounted, source: Node) -> Dictionary:
	var staged: Dictionary = baker.stage(source, SOURCE_PATH)
	var root: Node = (staged["runtime_scene"] as PackedScene).instantiate()
	var preview := Node2D.new()
	preview.name = "PreviewOnly"
	root.add_child(preview)
	preview.owner = root
	staged["runtime_scene"] = _pack_scene_root(root)
	root.free()
	return staged


func _stage_with_altered_metadata(baker: RefCounted, source: Node) -> Dictionary:
	var staged: Dictionary = baker.stage(source, SOURCE_PATH)
	var room_data: Resource = staged["room_data"]
	room_data.display_name = "Tampered Metadata"
	return staged


func _pack_scene_root(root: Node) -> PackedScene:
	for child: Node in root.get_children():
		_assign_owner_recursive(child, root)
	var scene := PackedScene.new()
	scene.pack(root)
	return scene


func _assign_owner_recursive(node: Node, root: Node) -> void:
	node.owner = root
	for child: Node in node.get_children():
		_assign_owner_recursive(child, root)


func _assert_result_envelope(result: Dictionary, label: String, failures: Array[String]) -> void:
	for key: String in ["ok", "errors", "warnings"]:
		if not result.has(key):
			failures.append("public result envelope omitted %s: %s" % [key, label])
	if not result.get("ok", null) is bool:
		failures.append("public result envelope has non-boolean ok: %s" % label)
	if not result.get("errors", null) is Array:
		failures.append("public result envelope has non-array errors: %s" % label)
	if not result.get("warnings", null) is Array:
		failures.append("public result envelope has non-array warnings: %s" % label)


func _assert_warnings(result: Dictionary, label: String, failures: Array[String]) -> void:
	if result.get("warnings", []) != ["test authoring warning"]:
		failures.append("authoring warnings were not preserved through %s" % label)


func _contains_error(result: Dictionary, fragment: String) -> bool:
	for error: String in result.get("errors", []):
		if error.contains(fragment):
			return true
	return false


func _contains_warning(result: Dictionary, fragment: String) -> bool:
	for warning: String in result.get("warnings", []):
		if warning.contains(fragment):
			return true
	return false


func _remove_final_outputs(paths: Dictionary) -> void:
	for final_path: String in _final_paths(paths):
		if FileAccess.file_exists(final_path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(final_path))


func _final_paths(paths: Dictionary) -> Array[String]:
	return [paths["runtime_scene_path"], paths["terrain_scene_path"], paths["room_resource_path"]]


func _make_source(include_resource_fixture := false, include_resource_cycle := false) -> Node:
	var root: Node2D = ROOM_AUTHORING_ROOT.new()
	root.room_id = ROOM_ID
	root.display_name = "Room Baker Test"
	root.room_size_chunks = Vector2i(2, 1)
	root.preview_spawn_id = "spawn_a"
	root.tags = PackedStringArray(["test", "authoring"])

	var room_content := Node2D.new()
	room_content.name = "RoomContent"
	root.add_child(room_content)

	var background := Node2D.new()
	background.name = "Background"
	background.position = Vector2(3.0, 5.0)
	var backdrop_child := Marker2D.new()
	backdrop_child.name = "BackdropChild"
	backdrop_child.position = Vector2(7.0, 11.0)
	background.add_child(backdrop_child)
	room_content.add_child(background)

	var terrain := Node2D.new()
	terrain.name = "Terrain"
	terrain.position = Vector2(13.0, 17.0)
	for layer_name: String in ["BackTiles", "SolidTiles", "GlassTiles", "VisionBlockTiles", "DetailTiles", "MarkerTiles"]:
		var layer := TileMapLayer.new()
		layer.name = layer_name
		terrain.add_child(layer)
	room_content.add_child(terrain)

	var entities := Node2D.new()
	entities.name = "Entities"
	var entrance: Node2D = ROOM_ENTRANCE.new()
	entrance.name = "RoomExit"
	entrance.entity_id = "exit_a"
	entrance.position = Vector2(19.0, 23.0)
	entities.add_child(entrance)
	var spawn: Marker2D = SPAWN_POINT.new()
	spawn.name = "SpawnA"
	spawn.spawn_id = "spawn_a"
	entities.add_child(spawn)
	var persistent: Node2D = WORLD_ENTITY.new()
	persistent.name = "PersistentSwitch"
	persistent.entity_id = "switch_a"
	persistent.persistent = true
	persistent.position = Vector2(29.0, 31.0)
	persistent.add_to_group("room_baker_runtime_group", true)
	var state_child := Marker2D.new()
	state_child.name = "StateChild"
	state_child.position = Vector2(37.0, 41.0)
	persistent.add_child(state_child)
	entities.add_child(persistent)
	room_content.add_child(entities)

	var foreground := Node2D.new()
	foreground.name = "Foreground"
	room_content.add_child(foreground)
	var creator_node: Node2D = SIGNATURE_FIXTURE_NODE.new() if include_resource_fixture else Node2D.new()
	creator_node.name = "CreatorNode"
	creator_node.position = Vector2(43.0, 47.0)
	if include_resource_fixture:
		var fixture_node: Node2D = creator_node
		var embedded_resource: Resource = EMBEDDED_SIGNATURE_RESOURCE.new()
		embedded_resource.resource_name = "embedded_signature"
		embedded_resource.first_value = "first"
		embedded_resource.later_value = "later"
		if include_resource_cycle:
			embedded_resource.cyclic_resource = embedded_resource
		fixture_node.set("embedded_resource", embedded_resource)
		fixture_node.set("mixed_values", {1: "integer one", "1": "string one", Vector2i(1, 1): "vector one", "(1, 1)": "vector text"})
	var creator_child := Marker2D.new()
	creator_child.name = "CreatorChild"
	creator_node.add_child(creator_child)
	room_content.add_child(creator_node)

	var preview := Node2D.new()
	preview.name = "PreviewOnly"
	var preview_marker := Marker2D.new()
	preview_marker.name = "PreviewMarker"
	preview.add_child(preview_marker)
	root.add_child(preview)
	return root


func _load_contract(paths: Dictionary, failures: Array[String]) -> Dictionary:
	var runtime_scene := ResourceLoader.load(paths["runtime_scene_path"], "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	var terrain_scene := ResourceLoader.load(paths["terrain_scene_path"], "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	var room_data := ResourceLoader.load(paths["room_resource_path"], "RoomData", ResourceLoader.CACHE_MODE_IGNORE) as Resource
	if runtime_scene == null or terrain_scene == null or room_data == null:
		failures.append("generated outputs could not all be reloaded")
		return {}
	var runtime_root: Node = runtime_scene.instantiate()
	var terrain_root: Node = terrain_scene.instantiate()
	var runtime_switch: Node = runtime_root.get_node_or_null("Entities/PersistentSwitch")
	var contract := {
		"runtime_root": runtime_root.name,
		"runtime_children": _direct_child_names(runtime_root),
		"terrain_root": terrain_root.name,
		"terrain_children": _direct_child_names(terrain_root),
		"runtime_has_switch": runtime_root.get_node_or_null("Entities/PersistentSwitch/StateChild") != null,
		"runtime_switch_has_world_entity_api": runtime_switch != null and runtime_switch.has_method("get_save_state"),
		"runtime_switch_position": _node_position(runtime_switch),
		"runtime_switch_group": _is_in_group(runtime_switch, "room_baker_runtime_group"),
		"runtime_creator_position": _node_position(runtime_root.get_node_or_null("CreatorNode")),
		"terrain_backdrop_position": _node_position(terrain_root.get_node_or_null("Background/BackdropChild")),
		"terrain_has_solid_tiles": terrain_root.get_node_or_null("Terrain/SolidTiles") is TileMapLayer,
		"room_id": room_data.room_id,
		"display_name": room_data.display_name,
		"scene_path": room_data.scene_path,
		"terrain_scene_path": room_data.terrain_scene_path,
		"source_scene_path": room_data.source_scene_path,
		"room_size_chunks": room_data.room_size_chunks,
		"entrance_ids": Array(room_data.entrance_ids),
		"spawn_ids": Array(room_data.spawn_ids),
		"entity_ids": Array(room_data.entity_ids),
		"tags": Array(room_data.tags),
		"room_origin_chunk": room_data.room_origin_chunk,
		"adjacent_room_ids": Array(room_data.adjacent_room_ids),
	}
	runtime_root.free()
	terrain_root.free()
	return contract


func _assert_split_contract(contract: Dictionary, paths: Dictionary, failures: Array[String]) -> void:
	if contract.is_empty():
		return
	if contract.get("runtime_root") != "RoomRuntimeContent":
		failures.append("runtime scene root name was not RoomRuntimeContent")
	if contract.get("terrain_root") != "RoomTerrain":
		failures.append("terrain scene root name was not RoomTerrain")
	if contract.get("runtime_children") != ["Entities", "Foreground", "CreatorNode"]:
		failures.append("runtime scene did not contain the expected direct RoomContent children")
	if contract.get("terrain_children") != ["Background", "Terrain"]:
		failures.append("terrain scene did not contain only Background and Terrain")
	if not contract.get("runtime_has_switch", false):
		failures.append("runtime scene did not serialize nested entity descendants")
	if not contract.get("runtime_switch_has_world_entity_api", false):
		failures.append("runtime entity script was not preserved")
	if contract.get("runtime_switch_position") != Vector2(29.0, 31.0):
		failures.append("runtime entity transform was not preserved")
	if not contract.get("runtime_switch_group", false):
		failures.append("runtime entity group was not preserved")
	if contract.get("runtime_creator_position") != Vector2(43.0, 47.0):
		failures.append("arbitrary creator node transform was not preserved")
	if contract.get("terrain_backdrop_position") != Vector2(7.0, 11.0):
		failures.append("terrain background descendant transform was not preserved")
	if not contract.get("terrain_has_solid_tiles", false):
		failures.append("terrain TileMapLayer descendants were not serialized")
	if ResourceLoader.exists(paths["runtime_scene_path"], "PackedScene") and ResourceLoader.exists(paths["terrain_scene_path"], "PackedScene"):
		return
	failures.append("generated scene paths were not valid PackedScene resources")


func _assert_room_metadata(contract: Dictionary, paths: Dictionary, failures: Array[String]) -> void:
	if contract.is_empty():
		return
	var expected := {
		"room_id": ROOM_ID,
		"display_name": "Room Baker Test",
		"scene_path": paths["runtime_scene_path"],
		"terrain_scene_path": paths["terrain_scene_path"],
		"source_scene_path": SOURCE_PATH,
		"room_size_chunks": Vector2i(2, 1),
		"entrance_ids": ["exit_a"],
		"spawn_ids": ["spawn_a"],
		"entity_ids": ["switch_a"],
		"tags": ["authoring", "test"],
		"room_origin_chunk": Vector2i.ZERO,
		"adjacent_room_ids": [],
	}
	for key: String in expected:
		if contract.get(key) != expected[key]:
			failures.append("generated RoomData mismatch: %s" % key)


func _assert_no_temporary_outputs(paths: Dictionary, failures: Array[String]) -> void:
	for path: String in _temporary_paths(paths):
		if FileAccess.file_exists(path):
			failures.append("temporary generated output remained: %s" % path)


func _any_output_exists(paths: Dictionary) -> bool:
	for path: String in _all_paths(paths):
		if FileAccess.file_exists(path):
			return true
	return false


func _cleanup(paths: Dictionary) -> void:
	for path: String in _all_paths(paths):
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _all_paths(paths: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for final_path: String in [paths["runtime_scene_path"], paths["terrain_scene_path"], paths["room_resource_path"]]:
		result.append(final_path)
		result.append(_marked_path(final_path, ".stage"))
		result.append(_marked_path(final_path, ".backup"))
	return result


func _temporary_paths(paths: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for final_path: String in [paths["runtime_scene_path"], paths["terrain_scene_path"], paths["room_resource_path"]]:
		result.append(_marked_path(final_path, ".stage"))
		result.append(_marked_path(final_path, ".backup"))
	return result


func _marked_path(path: String, marker: String) -> String:
	var extension_start := path.rfind(".")
	return "%s%s%s" % [path.left(extension_start), marker, path.substr(extension_start)]


func _direct_child_names(root: Node) -> Array[String]:
	var names: Array[String] = []
	for child: Node in root.get_children():
		names.append(str(child.name))
	return names


func _node_position(node: Node) -> Vector2:
	if node is Node2D:
		return (node as Node2D).position
	return Vector2.INF


func _is_in_group(node: Node, group_name: String) -> bool:
	return node != null and node.is_in_group(group_name)
