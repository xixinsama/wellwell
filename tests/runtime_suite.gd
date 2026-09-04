extends Node

const TESTS: Array[Script] = [
	preload("res://tests/save/test_save_codec.gd"),
	preload("res://tests/save/test_save_storage.gd"),
	preload("res://tests/world/test_fog_visibility.gd"),
	preload("res://tests/world/test_tilemap_scene_contract.gd"),
	preload("res://tests/world/test_world_data.gd"),
	preload("res://tests/world/test_world_validation.gd"),
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
