extends Node

const TESTS: Array[Script] = [
	preload("res://tests/save/test_save_codec.gd"),
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
