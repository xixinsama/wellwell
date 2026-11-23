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

const TESTS: Array[Script] = [
	preload("res://tests/input_mapping/test_input_mapping_model.gd"),
	preload("res://tests/input_mapping/test_input_mapping_service.gd"),
	preload("res://tests/input_mapping/test_input_mapping_ui.gd"),
	preload("res://tests/platformer_kit/test_platformer_kit_contract.gd"),
	preload("res://tests/platformer_kit/test_core_primitives.gd"),
	preload("res://tests/platformer_kit/character/test_character_intent.gd"),
	preload("res://tests/platformer_kit/character/test_input_source.gd"),
	preload("res://tests/platformer_kit/character/test_movement_profile.gd"),
	preload("res://tests/platformer_kit/character/test_character_motor_2d.gd"),
	preload("res://tests/platformer_kit/character/test_character_motor_integration.gd"),
	preload("res://tests/platformer_kit/character/test_character_sensors.gd"),
	preload("res://tests/platformer_kit/platforms/test_platform_motion.gd"),
	preload("res://tests/platformer_kit/platforms/test_fog_occluder.gd"),
	preload("res://tests/platformer_kit/platforms/test_elevator_motion.gd"),
	preload("res://tests/platformer_kit/interaction/test_interaction.gd"),
	preload("res://tests/examples/test_movement_lab.gd"),
	preload("res://tests/examples/test_ability_lab.gd"),
	preload("res://tests/platformer_kit/world/test_world_contract_independence.gd"),
	preload("res://tests/platformer_kit/save/test_save_contracts.gd"),
	preload("res://tests/platformer_debug/test_debug_contract.gd"),
	preload("res://tests/platformer_debug/test_tas_input_source.gd"),
	preload("res://tests/platformer_debug/test_tas_tool_hotkeys.gd"),
	preload("res://tests/platformer_kit/abilities/test_ability_runtime.gd"),
	preload("res://tests/platformer_kit/abilities/test_ability_pickup.gd"),
	preload("res://tests/platformer_kit/abilities/test_dash_ability.gd"),
	preload("res://tests/platformer_kit/abilities/test_climb_ability.gd"),
	preload("res://tests/game/test_player_ability_loadout.gd"),
	preload("res://tests/game/test_one_way_dash_pierce.gd"),
	preload("res://tests/game/test_player_interaction.gd"),
	preload("res://tests/game/test_collectibles.gd"),
	preload("res://tests/game/test_number_pickup.gd"),
	preload("res://tests/platformer_kit/combat/test_combat_runtime.gd"),
	preload("res://tests/platformer_kit/abilities/test_ability_combat_contract.gd"),
	preload("res://tests/metroidvania_kit/test_progression_conditions.gd"),
	preload("res://tests/metroidvania_kit/test_map_discovery.gd"),
	preload("res://tests/metroidvania_kit/test_map_runtime_persistence.gd"),
	preload("res://tests/metroidvania_kit/test_map_rendering.gd"),
	preload("res://tests/metroidvania_kit/test_metroidvania_contract.gd"),
	preload("res://tests/authoring/room/test_room_bake_paths.gd"),
	preload("res://tests/authoring/room/test_source_fingerprint.gd"),
	preload("res://tests/authoring/test_room_authoring_contract.gd"),
	preload("res://tests/authoring/test_room_bake_model.gd"),
	preload("res://tests/authoring/test_room_baker.gd"),
	preload("res://tests/authoring/test_room_cell_crop.gd"),
	preload("res://tests/authoring/test_room_cell_frame.gd"),
	preload("res://tests/authoring/test_room_terrain_slice.gd"),
	preload("res://tests/authoring/test_room_partition.gd"),
	preload("res://tests/authoring/test_room_partition_workflow.gd"),
	preload("res://tests/authoring/test_world_room_draw.gd"),
	preload("res://tests/authoring/test_world_preview_zoom.gd"),
	preload("res://tests/authoring/test_room_preview_controller.gd"),
	preload("res://tests/authoring/test_room_preview_spawn_auto.gd"),
	preload("res://tests/authoring/test_level_template_contract.gd"),
	preload("res://tests/authoring/test_world_layout_model.gd"),
	preload("res://tests/authoring/test_world_baker.gd"),
	preload("res://tests/authoring/test_world_resource_service.gd"),
	preload("res://tests/authoring/test_world_room_importer.gd"),
	preload("res://tests/authoring/test_world_canvas_view.gd"),
	preload("res://tests/authoring/test_world_stack_model.gd"),
	preload("res://tests/authoring/test_world_stack_camera.gd"),
	preload("res://tests/authoring/test_world_stack_3d_layer.gd"),
	preload("res://tests/authoring/test_world_editor_main_screen.gd"),
	preload("res://tests/authoring/test_world_terrain_preview_layer.gd"),
	preload("res://tests/authoring/test_world_editor_commands.gd"),
	preload("res://tests/authoring/test_room_status.gd"),
	preload("res://tests/authoring/test_room_annotations.gd"),
	preload("res://tests/authoring/test_world_canvas_selection.gd"),
	preload("res://tests/authoring/test_world_editor_localization.gd"),
	preload("res://tests/authoring/test_components_gallery.gd"),
	preload("res://tests/authoring/test_room_scene_writer.gd"),
	preload("res://tests/world_editor/test_world_editor_framework_boundary.gd"),
	preload("res://tests/save/test_save_codec.gd"),
	preload("res://tests/save/test_save_storage.gd"),
	preload("res://tests/save/test_save_slots.gd"),
	preload("res://tests/save/test_realtime_save.gd"),
	preload("res://tests/save/test_realtime_save_integration.gd"),
	preload("res://tests/world/test_fog_visibility.gd"),
	preload("res://tests/world/test_crumble_runtime.gd"),
	preload("res://tests/world/test_fog_door.gd"),
	preload("res://tests/world/test_phantom_wall.gd"),
	preload("res://tests/puzzle/test_sliding_puzzle_core.gd"),
	preload("res://tests/puzzle/test_piece_fog_occlusion.gd"),
	preload("res://tests/puzzle/test_one_way_occupancy.gd"),
	preload("res://tests/puzzle/test_puzzle_void_zone.gd"),
	preload("res://tests/puzzle/test_void_slider.gd"),
	preload("res://tests/puzzle/test_start_room_void.gd"),
	preload("res://tests/puzzle/test_puzzle_history.gd"),
	preload("res://tests/puzzle/test_piece_enable.gd"),
	preload("res://tests/puzzle/test_gamepad_selection.gd"),
	preload("res://tests/puzzle/test_gamepad_stick_aim.gd"),
	preload("res://tests/puzzle/test_rider_jump_reset.gd"),
	preload("res://tests/puzzle/test_puzzle_tile_piece.gd"),
	preload("res://tests/puzzle/test_puzzle_board_auto.gd"),
	preload("res://tests/puzzle/test_puzzle_board_shuffler.gd"),
	preload("res://tests/puzzle/test_puzzle_auto_room.gd"),
	preload("res://tests/puzzle/test_puzzle_room_contract.gd"),
	preload("res://tests/world/data/test_room_grid.gd"),
	preload("res://tests/world/test_pixel_camera.gd"),
	preload("res://tests/world/test_runtime_bindings.gd"),
	preload("res://tests/world/test_tilemap_scene_contract.gd"),
	preload("res://tests/world/test_world_data.gd"),
	preload("res://tests/world/test_world_stack_data.gd"),
	preload("res://tests/world/test_world_validation.gd"),
	preload("res://tests/world/test_room_runtime.gd"),
	preload("res://tests/world/test_world_terrain_runtime.gd"),
	preload("res://tests/world/test_world_runtime.gd"),
	preload("res://tests/world/test_world_session.gd"),
	preload("res://tests/world/test_world_entity.gd"),
	preload("res://tests/world/test_save_point.gd"),
	preload("res://tests/world/test_world_door.gd"),
	preload("res://tests/world/test_world_travel.gd"),
	preload("res://tests/world/test_map_model.gd"),
	preload("res://tests/world/test_room_transition.gd"),
	preload("res://tests/tools/test_project_validation.gd"),
	preload("res://tests/tools/test_script_hygiene.gd"),
	preload("res://tests/tools/test_framework_boundaries.gd"),
	preload("res://tests/tools/test_framework_documentation_contract.gd"),
	preload("res://tests/tools/test_suite_registration.gd"),
	preload("res://tests/ui/test_menu_contract.gd"),
	preload("res://tests/ui/test_menu_features.gd"),
	preload("res://tests/ui/test_settings_pages.gd"),
	preload("res://tests/ui/test_world_select.gd"),
	preload("res://tests/ui/test_interaction_prompt.gd"),
	preload("res://tests/ui/test_collection_screen.gd"),
	preload("res://tests/player/test_player_motion_effects.gd"),
	preload("res://tests/player/test_celeste_movement_rules.gd"),
	preload("res://tests/world/test_killzone.gd"),
	preload("res://tests/world/test_spike_hazard.gd"),
	preload("res://tests/platformer_kit/character/test_ladder_motion.gd"),
	preload("res://tests/world/test_ladder_tiles.gd"),
	preload("res://tests/world/test_cell_rect_merger.gd"),
	preload("res://tests/world/test_terrain_highlight.gd"),
	preload("res://tests/world/test_light_field.gd"),
	preload("res://tests/world/test_backdrop_field.gd"),
	preload("res://tests/player/test_hero_animation.gd"),
	preload("res://tests/world/test_water_simulation.gd"),
	preload("res://tests/world/test_water_grid.gd"),
	preload("res://tests/world/test_water_grid_room.gd"),
	preload("res://tests/world/test_atmosphere_fog.gd"),
	preload("res://tests/world/test_atmosphere_settings.gd"),
	preload("res://tests/world/test_gas_backend.gd"),
	preload("res://tests/world/test_gas_dither_seam.gd"),
	preload("res://tests/world/test_blue_noise.gd"),
	preload("res://tests/world/test_gas_solver.gd"),
	preload("res://tests/world/test_water_buoyancy.gd"),
	preload("res://tests/world/test_water_room_contract.gd"),
	preload("res://tests/world/test_normal_field.gd"),
	preload("res://tests/world/test_tileset_normals.gd"),
	preload("res://tests/world/test_tileset_terrain.gd"),
	preload("res://tests/world/test_water_ripple_reach.gd"),
	preload("res://tests/world/test_water_surface_ripple_reach.gd"),
	preload("res://tests/world/test_backdrop_shadow.gd"),
	preload("res://tests/world/test_dust_field.gd"),
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
