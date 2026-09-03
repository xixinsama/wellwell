extends SceneTree


func _init() -> void:
	var suite := preload("res://tests/runtime_suite.gd").new()
	root.add_child(suite)
	quit(0 if suite.run() else 1)
