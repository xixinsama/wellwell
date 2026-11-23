class_name Minimap
extends Control

@export var tracked_room_id: StringName
var runtime: RefCounted


func bind_runtime(value: RefCounted) -> void:
	runtime = value
	$Renderer.bind_runtime(value)


func refresh() -> void:
	if runtime != null:
		tracked_room_id = StringName(runtime.get("current_room_id"))
	$Renderer.queue_redraw()
