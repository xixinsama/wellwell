extends SceneTree

## Entry point for the headless runtime suite.
##   godot --headless --path . -s res://tests/run_runtime_suite.gd
##   godot --headless --path . -s res://tests/run_runtime_suite.gd -- --group=world
##   godot --headless --path . -s res://tests/run_runtime_suite.gd -- --group=player,ui

func _init() -> void:
	call_deferred("_run_suite")


func _run_suite() -> void:
	var group := ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--group="):
			group = argument.trim_prefix("--group=")
	var suite := preload("res://tests/runtime_suite.gd").new()
	root.add_child(suite)
	quit(0 if suite.run(group) else 1)
