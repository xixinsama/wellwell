extends Node

## Headless runtime suite. Every test is a Node script exposing
## `run() -> Array[String]`; an empty array means success.
##
## Run everything:      godot --headless --path . -s res://tests/run_runtime_suite.gd
## Run one group:       godot --headless --path . -s res://tests/run_runtime_suite.gd -- --group=world
## Run several groups:  godot --headless --path . -s res://tests/run_runtime_suite.gd -- --group=world,ui
##
## A group is the folder under `tests/`, so `--group=platformer_kit` runs the
## whole kit (including `platformer_kit/abilities` and `platformer_kit/combat`).
## Keep this list in sync: tests/tools/test_suite_registration.gd fails otherwise.

const TESTS: Array[Script] = [
	preload("res://tests/authoring/test_room_authoring.gd"),
	preload("res://tests/authoring/test_room_authoring_contract.gd"),
	preload("res://tests/authoring/test_room_bake.gd"),
	preload("res://tests/authoring/test_room_baker.gd"),
	preload("res://tests/authoring/test_room_partition.gd"),
	preload("res://tests/authoring/test_room_partition_workflow.gd"),
	preload("res://tests/authoring/test_room_preview_controller.gd"),
	preload("res://tests/authoring/test_world_baker.gd"),
	preload("res://tests/authoring/test_world_canvas_view.gd"),
	preload("res://tests/authoring/test_world_editor_commands.gd"),
	preload("res://tests/authoring/test_world_layout_model.gd"),
	preload("res://tests/authoring/test_world_resource_service.gd"),
	preload("res://tests/authoring/test_world_room_importer.gd"),
	preload("res://tests/authoring/test_world_stack.gd"),
	preload("res://tests/authoring/test_world_stack_3d_layer.gd"),
	preload("res://tests/examples/test_examples.gd"),
	preload("res://tests/game/test_game_content.gd"),
	preload("res://tests/game/test_one_way_dash_pierce.gd"),
	preload("res://tests/game/test_player_ability_loadout.gd"),
	preload("res://tests/input_mapping/test_input_mapping_model.gd"),
	preload("res://tests/input_mapping/test_input_mapping_service.gd"),
	preload("res://tests/input_mapping/test_input_mapping_ui.gd"),
	preload("res://tests/metroidvania_kit/test_map_core.gd"),
	preload("res://tests/metroidvania_kit/test_map_rendering.gd"),
	preload("res://tests/metroidvania_kit/test_map_runtime_persistence.gd"),
	preload("res://tests/platformer_debug/test_debug_contract.gd"),
	preload("res://tests/platformer_debug/test_tas.gd"),
	preload("res://tests/platformer_kit/abilities/test_abilities.gd"),
	preload("res://tests/platformer_kit/abilities/test_dash_ability.gd"),
	preload("res://tests/platformer_kit/character/test_autopilot.gd"),
	preload("res://tests/platformer_kit/character/test_character_input.gd"),
	preload("res://tests/platformer_kit/character/test_character_motor_2d.gd"),
	preload("res://tests/platformer_kit/character/test_character_motor_integration.gd"),
	preload("res://tests/platformer_kit/character/test_ladder_motion.gd"),
	preload("res://tests/platformer_kit/combat/test_combat_runtime.gd"),
	preload("res://tests/platformer_kit/interaction/test_interaction.gd"),
	preload("res://tests/platformer_kit/platforms/test_platforms.gd"),
	preload("res://tests/platformer_kit/save/test_save_contracts.gd"),
	preload("res://tests/platformer_kit/test_kit_contract.gd"),
	preload("res://tests/platformer_kit/world/test_world_contract_independence.gd"),
	preload("res://tests/player/test_celeste_movement_rules.gd"),
	preload("res://tests/player/test_hero_animation.gd"),
	preload("res://tests/player/test_player_motion_effects.gd"),
	preload("res://tests/puzzle/test_puzzle_board.gd"),
	preload("res://tests/puzzle/test_puzzle_input.gd"),
	preload("res://tests/puzzle/test_puzzle_pieces.gd"),
	preload("res://tests/save/test_save.gd"),
	preload("res://tests/tools/test_framework_boundaries.gd"),
	preload("res://tests/tools/test_framework_documentation_contract.gd"),
	preload("res://tests/tools/test_project_validation.gd"),
	preload("res://tests/tools/test_script_hygiene.gd"),
	preload("res://tests/tools/test_suite_registration.gd"),
	preload("res://tests/tools/test_project_layout.gd"),
	preload("res://tests/ui/test_menu_features.gd"),
	preload("res://tests/ui/test_ui_screens.gd"),
	preload("res://tests/world/test_fog_visibility.gd"),
	preload("res://tests/world/test_light_field.gd"),
	preload("res://tests/world/test_normal_field.gd"),
	preload("res://tests/world/test_terrain_highlight.gd"),
	preload("res://tests/world/test_tilesets.gd"),
	preload("res://tests/world/test_water_grid.gd"),
	preload("res://tests/world/test_world_contract.gd"),
	preload("res://tests/world/test_world_entities.gd"),
	preload("res://tests/world/test_world_gas.gd"),
	preload("res://tests/world/test_world_rendering.gd"),
	preload("res://tests/world/test_world_runtime.gd"),
	preload("res://tests/world/test_world_runtime_bindings.gd"),
	preload("res://tests/world/test_world_session.gd"),
	preload("res://tests/world/test_world_travel.gd"),
	preload("res://tests/world/test_world_water.gd"),
	preload("res://tests/world_editor/test_world_editor_framework_boundary.gd"),
]


func run(group: String = "") -> bool:
	var selected := _select(group)
	if selected.is_empty():
		push_error("runtime suite: no tests matched group '%s'" % group)
		return false
	var failures: Array[String] = []
	for test_script: Script in selected:
		var test: Node = test_script.new() as Node
		add_child(test)
		failures.append_array(test.run())
		test.queue_free()
	var scope := "all" if group.is_empty() else group
	print("runtime suite [%s]: %d tests, %d failures" % [scope, selected.size(), failures.size()])
	for failure: String in failures:
		push_error(failure)
	return failures.is_empty()


func _select(group: String) -> Array[Script]:
	if group.strip_edges().is_empty():
		return TESTS
	var prefixes := PackedStringArray()
	for part: String in group.split(",", false):
		prefixes.append(part.strip_edges())
	var selected: Array[Script] = []
	for test_script: Script in TESTS:
		var relative := test_script.resource_path.trim_prefix("res://tests/")
		for prefix: String in prefixes:
			if relative.begins_with(prefix + "/") or relative.get_basename() == prefix:
				selected.append(test_script)
				break
	return selected
