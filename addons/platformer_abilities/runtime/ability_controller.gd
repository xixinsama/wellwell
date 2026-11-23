class_name AbilityController
extends Node

const BASE_RUNTIME := preload("res://addons/platformer_abilities/runtime/ability_runtime.gd")

var _runtimes: Dictionary[StringName, RefCounted] = {}


func _physics_process(delta: float) -> void:
	tick(delta)


func add_definition(definition: Resource) -> bool:
	if definition == null:
		return false
	var ability_id := StringName(definition.get("ability_id"))
	if ability_id.is_empty() or _runtimes.has(ability_id):
		return false
	var runtime_script := definition.get("runtime_script") as Script
	if runtime_script != null and not _script_inherits(runtime_script, BASE_RUNTIME):
		return false
	var runtime: RefCounted = (runtime_script.new() if runtime_script != null else BASE_RUNTIME.new()) as RefCounted
	if runtime == null or not _has_runtime_contract(runtime):
		return false
	runtime.call("configure", definition)
	_runtimes[ability_id] = runtime
	return true


func remove_ability(ability_id: StringName) -> bool:
	return _runtimes.erase(ability_id)


func has_ability(ability_id: StringName) -> bool:
	return _runtimes.has(ability_id)


func get_runtime(ability_id: StringName) -> RefCounted:
	return _runtimes.get(ability_id)


func try_activate(ability_id: StringName, context: RefCounted) -> bool:
	var runtime := get_runtime(ability_id)
	return runtime != null and bool(runtime.call("activate", context))


func cancel(ability_id: StringName) -> bool:
	var runtime := get_runtime(ability_id)
	return runtime != null and bool(runtime.call("cancel"))


func tick(delta: float) -> void:
	for runtime: RefCounted in _runtimes.values():
		runtime.call("tick", delta)


func ability_ids() -> Array[StringName]:
	var result: Array[StringName] = []
	result.assign(_runtimes.keys())
	result.sort()
	return result


func _has_runtime_contract(runtime: RefCounted) -> bool:
	for method: StringName in [&"configure", &"activate", &"cancel", &"tick"]:
		if not runtime.has_method(method):
			return false
	return true


func _script_inherits(script: Script, expected_base: Script) -> bool:
	var current: Script = script
	while current != null:
		if current == expected_base:
			return true
		current = current.get_base_script()
	return false
