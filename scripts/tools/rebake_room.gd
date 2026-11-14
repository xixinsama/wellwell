extends SceneTree

const ROOM_BAKER := preload("res://addons/world_editor/authoring/room/room_baker.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 1:
		push_error("usage: -- res://scenes/levels/room_01_00.tscn")
		quit(2)
		return
	var packed := load(args[0]) as PackedScene
	if packed == null:
		push_error("could not load source room")
		quit(1)
		return
	var source := packed.instantiate()
	var result: Dictionary = ROOM_BAKER.new().bake(source, args[0])
	source.free()
	if not result.get("ok", false):
		push_error("room bake failed: %s" % str(result.get("errors", [])))
		quit(1)
		return
	quit(0)
