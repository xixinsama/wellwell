extends SceneTree


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		push_error("usage: -- res://tests/path/test_file.gd")
		quit(2)
		return
	var test_script := load(args[0]) as Script
	if test_script == null:
		push_error("test script could not be loaded: %s" % args[0])
		quit(2)
		return
	var test := test_script.new() as Node
	if test == null or not test.has_method("run"):
		push_error("test must be a Node exposing run()")
		quit(2)
		return
	root.add_child(test)
	var failures: Array[String] = test.run()
	for failure: String in failures:
		push_error(failure)
	test.queue_free()
	quit(0 if failures.is_empty() else 1)
