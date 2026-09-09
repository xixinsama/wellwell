class_name AbilityRuntime
extends RefCounted

signal activated(context: RefCounted)
signal cancelled
signal cooldown_finished

var definition: Resource
var active := false
var cooldown_remaining := 0.0
var last_context: RefCounted


func configure(value: Resource) -> void:
	definition = value
	active = false
	cooldown_remaining = 0.0
	last_context = null


func can_activate(context: RefCounted) -> bool:
	if definition == null or not bool(definition.get("enabled")):
		return false
	if active or cooldown_remaining > 0.0 or context == null:
		return false
	if not context.has_method("has_all_tags"):
		return false
	if not context.call("has_all_tags", definition.get("required_tags")):
		return false
	for tag: StringName in definition.get("blocked_tags"):
		if context.call("has_tag", tag):
			return false
	return _can_activate(context)


func activate(context: RefCounted) -> bool:
	if not can_activate(context):
		return false
	active = true
	last_context = context
	cooldown_remaining = maxf(0.0, float(definition.get("cooldown_seconds")))
	_on_activate(context)
	activated.emit(context)
	return true


func cancel() -> bool:
	if not active:
		return false
	active = false
	_on_cancel()
	cancelled.emit()
	return true


func finish() -> bool:
	if not active:
		return false
	active = false
	_on_finish()
	return true


func tick(delta: float) -> void:
	if active:
		_on_tick(maxf(delta, 0.0))
	if cooldown_remaining <= 0.0:
		return
	var previous := cooldown_remaining
	cooldown_remaining = maxf(0.0, cooldown_remaining - maxf(delta, 0.0))
	if previous > 0.0 and cooldown_remaining == 0.0:
		cooldown_finished.emit()


func _can_activate(_context: RefCounted) -> bool:
	return true


func _on_activate(_context: RefCounted) -> void:
	pass


func _on_cancel() -> void:
	pass


func _on_finish() -> void:
	pass


func _on_tick(_delta: float) -> void:
	pass
