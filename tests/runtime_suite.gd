extends Node

const TESTS: Array[Script] = [
	preload("res://tests/authoring/test_room_authoring_contract.gd"),
	preload("res://tests/authoring/test_room_bake_model.gd"),
	preload("res://tests/authoring/test_room_baker.gd"),
	preload("res://tests/authoring/test_room_preview_controller.gd"),
	preload("res://tests/authoring/test_level_template_contract.gd"),
	preload("res://tests/authoring/test_world_layout_model.gd"),
	preload("res://tests/authoring/test_world_baker.gd"),
	preload("res://tests/authoring/test_world_resource_service.gd"),
	preload("res://tests/authoring/test_world_room_importer.gd"),
	preload("res://tests/authoring/test_world_canvas_view.gd"),
	preload("res://tests/authoring/test_world_editor_main_screen.gd"),
	preload("res://tests/authoring/test_world_editor_commands.gd"),
	preload("res://tests/save/test_save_codec.gd"),
	preload("res://tests/save/test_save_storage.gd"),
	preload("res://tests/save/test_save_slots.gd"),
	preload("res://tests/world/test_fog_visibility.gd"),
	preload("res://tests/world/test_runtime_bindings.gd"),
	preload("res://tests/world/test_tilemap_scene_contract.gd"),
	preload("res://tests/world/test_world_data.gd"),
	preload("res://tests/world/test_world_validation.gd"),
	preload("res://tests/world/test_room_runtime.gd"),
	preload("res://tests/world/test_world_terrain_runtime.gd"),
	preload("res://tests/world/test_world_runtime.gd"),
	preload("res://tests/world/test_world_session.gd"),
	preload("res://tests/world/test_world_entity.gd"),
	preload("res://tests/world/test_map_model.gd"),
	preload("res://tests/world/test_room_transition.gd"),
	preload("res://tests/tools/test_project_validation.gd"),
	preload("res://tests/ui/test_menu_contract.gd"),
	preload("res://tests/ui/test_menu_features.gd"),
]


func run() -> bool:
	var failures: Array[String] = []
	for test_script: Script in TESTS:
		var test: Node = test_script.new() as Node
		add_child(test)
		failures.append_array(test.run())
		test.queue_free()
	for failure: String in failures:
		push_error(failure)
	return failures.is_empty()
