class_name GameEvent
extends RefCounted

var topic: StringName
var payload: Variant


func _init(event_topic: StringName = &"", event_payload: Variant = null) -> void:
	topic = event_topic
	payload = event_payload

