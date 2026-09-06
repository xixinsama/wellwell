extends SceneTree


func _init() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	var arguments := OS.get_cmdline_user_args()
	if arguments.size() != 1:
		push_error("usage: run_test_script.gd -- <res://test_script.gd>")
		quit(2)
		return
	var test_script := load(arguments[0]) as Script
	if test_script == null or not test_script.can_instantiate():
		push_error("test script could not be loaded: %s" % arguments[0])
		quit(2)
		return
	var test := test_script.new() as Node
	if test == null or not test.has_method("run"):
		push_error("test script must create a Node exposing run(): %s" % arguments[0])
		quit(2)
		return
	root.add_child(test)
	var failures: Array = test.run()
	for failure: Variant in failures:
		push_error(String(failure))
	quit(0 if failures.is_empty() else 1)
