extends Node

const DEFINITION_PATH := "res://addons/platformer_abilities/runtime/ability_definition.gd"
const CONTEXT_PATH := "res://addons/platformer_abilities/runtime/ability_context.gd"
const RUNTIME_PATH := "res://addons/platformer_abilities/runtime/ability_runtime.gd"
const CONTROLLER_PATH := "res://addons/platformer_abilities/runtime/ability_controller.gd"
const INCOMPLETE_RUNTIME_PATH := "res://tests/platformer_abilities/incomplete_ability_runtime.gd"


func run() -> Array[String]:
	var failures: Array[String] = []
	var definition_script := load(DEFINITION_PATH) as Script
	var context_script := load(CONTEXT_PATH) as Script
	var runtime_script := load(RUNTIME_PATH) as Script
	var controller_script := load(CONTROLLER_PATH) as Script
	if definition_script == null or context_script == null or runtime_script == null or controller_script == null:
		failures.append("ability runtime scripts are missing")
		return failures

	var definition: Resource = definition_script.new()
	definition.set("ability_id", &"dash")
	definition.set("cooldown_seconds", 0.5)
	definition.set("required_tags", Array([&"grounded"], TYPE_STRING_NAME, &"", null))
	var context: RefCounted = context_script.new()
	context.call("add_tag", &"grounded")
	var runtime: RefCounted = runtime_script.new()
	runtime.call("configure", definition)
	if not runtime.call("can_activate", context):
		failures.append("eligible ability could not activate")
	if not runtime.call("activate", context) or not runtime.get("active"):
		failures.append("ability activation did not enter active state")
	if not runtime.call("cancel") or runtime.get("active"):
		failures.append("ability cancellation did not leave active state")
	if not is_equal_approx(float(runtime.get("cooldown_remaining")), 0.5):
		failures.append("ability activation did not start its cooldown")
	if runtime.call("can_activate", context):
		failures.append("ability ignored its active cooldown")
	runtime.call("tick", 0.5)
	if not runtime.call("can_activate", context):
		failures.append("ability did not become eligible after cooldown")

	var missing_tag_context: RefCounted = context_script.new()
	if runtime.call("can_activate", missing_tag_context):
		failures.append("ability ignored required context tags")

	var controller: Node = controller_script.new()
	if not controller.call("add_definition", definition):
		failures.append("ability controller rejected a valid definition")
	if controller.call("get_runtime", &"dash") == null:
		failures.append("ability controller did not create runtime state")
	var invalid_definition: Resource = definition_script.new()
	invalid_definition.set("ability_id", &"invalid")
	invalid_definition.set("runtime_script", load(INCOMPLETE_RUNTIME_PATH))
	if controller.call("add_definition", invalid_definition):
		failures.append("ability controller accepted an incomplete runtime contract")
	controller.free()
	return failures
