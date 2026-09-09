extends Node

const CONTEXT := "res://addons/metroidvania_kit/progression/progression_context.gd"
const HAS_ABILITY := "res://addons/metroidvania_kit/progression/conditions/has_ability_condition.gd"
const HAS_ITEM := "res://addons/metroidvania_kit/progression/conditions/has_item_condition.gd"
const FLAG := "res://addons/metroidvania_kit/progression/conditions/flag_condition.gd"
const COMPOSITE := "res://addons/metroidvania_kit/progression/conditions/composite_condition.gd"
const GATE := "res://addons/metroidvania_kit/gates/progression_gate.gd"


func run() -> Array[String]:
	var failures: Array[String] = []
	var paths := [CONTEXT, HAS_ABILITY, HAS_ITEM, FLAG, COMPOSITE, GATE]
	var scripts: Array[Script] = []
	for path: String in paths:
		var script := load(path) as Script
		if script == null:
			failures.append("progression script is missing: %s" % path)
		else:
			scripts.append(script)
	if not failures.is_empty():
		return failures

	var context: RefCounted = scripts[0].new()
	context.call("grant_ability", &"dash")
	context.call("grant_item", &"blue_key", 1)
	context.call("set_flag", &"boss:warden:defeated", true)
	var ability: Resource = scripts[1].new()
	ability.set("ability_id", &"dash")
	var item: Resource = scripts[2].new()
	item.set("item_id", &"blue_key")
	item.set("minimum_count", 1)
	var flag: Resource = scripts[3].new()
	flag.set("flag_id", &"boss:warden:defeated")
	flag.set("expected_value", true)
	for condition: Resource in [ability, item, flag]:
		if not condition.call("evaluate", context):
			failures.append("progression condition rejected satisfied context")
	var composite: Resource = scripts[4].new()
	var child_conditions: Array[Resource] = [ability, item, flag]
	composite.set("conditions", child_conditions)
	if not composite.call("evaluate", context):
		failures.append("composite condition did not evaluate all children")
	context.call("revoke_ability", &"dash")
	if composite.call("evaluate", context):
		failures.append("composite condition ignored a denied child")
	var gate: Node = scripts[5].new()
	gate.set("condition", composite)
	if gate.call("allows", context):
		failures.append("gate approved a denied progression context")
	context.call("grant_ability", &"dash")
	if not gate.call("allows", context):
		failures.append("gate denied a satisfied progression context")
	gate.free()
	return failures
