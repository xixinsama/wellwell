extends Node

## Merged test suite. Every inner class below is one original test file,
## kept in its own class so fixtures and helper names stay isolated. Do not
## add logic here: split a class back into its own file when it grows.

## tests/metroidvania_kit/test_progression_conditions.gd
class ProgressionConditionsCase extends Node:
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


## tests/metroidvania_kit/test_metroidvania_contract.gd
class MetroidvaniaContractCase extends Node:
	const MANIFEST := "res://addons/metroidvania_kit/plugin.cfg"
	const DEMO := "res://examples/metroidvania_demo/metroidvania_demo.tscn"
	const MOVEMENT_LAB := "res://examples/movement_lab/movement_lab.tscn"
	const FOG := "res://addons/metroidvania_kit/map/discovery/fog_of_war.gd"
	const FOG_VISIBILITY := "res://addons/metroidvania_kit/map/discovery/fog_visibility.gd"
	const MAP_VIEW := "res://addons/metroidvania_kit/map/ui/map_view.tscn"
	const MINIMAP := "res://addons/metroidvania_kit/map/ui/minimap.tscn"
	const MAP_RENDERER := "res://addons/metroidvania_kit/map/ui/map_renderer.gd"
	const MAIN_SCRIPT := "res://game/app/main.gd"


	class FakeDiscovery extends RefCounted:
		signal state_changed(room_id: StringName, previous_state: int, current_state: int)


	class FakeRuntime extends RefCounted:
		signal current_room_changed(previous_room_id: StringName, current_room_id: StringName)
		var discovery := FakeDiscovery.new()
		var definition: Resource


	func run() -> Array[String]:
		var failures: Array[String] = []
		var config := ConfigFile.new()
		if config.load(MANIFEST) != OK:
			failures.append("metroidvania_kit manifest is missing")
		for path: String in [DEMO, MAP_VIEW, MINIMAP]:
			if load(path) as PackedScene == null:
				failures.append("metroidvania scene is missing: %s" % path)
		for path: String in [FOG, FOG_VISIBILITY]:
			var script := load(path) as Script
			if script == null or not script.can_instantiate():
				failures.append("metroidvania fog strategy is missing: %s" % path)
		var movement_source := FileAccess.get_file_as_string(MOVEMENT_LAB)
		if movement_source.contains("metroidvania_kit"):
			failures.append("base movement lab depends on metroidvania_kit")
		var main_source := FileAccess.get_file_as_string(MAIN_SCRIPT)
		if not main_source.contains("MAP_DEFINITION_BUILDER.from_world"):
			failures.append("reference game does not build its map from the running world")
		var renderer_script := load(MAP_RENDERER) as Script
		if renderer_script != null:
			var renderer: Control = renderer_script.new()
			var fake_runtime := FakeRuntime.new()
			renderer.call("bind_runtime", fake_runtime)
			if not fake_runtime.is_connected("current_room_changed", Callable(renderer, "_on_runtime_changed")):
				failures.append("map renderer does not refresh when the tracked room changes")
			if not fake_runtime.discovery.is_connected("state_changed", Callable(renderer, "_on_discovery_changed")):
				failures.append("map renderer does not refresh when discovery changes")
			renderer.free()
		var demo_scene := load(DEMO) as PackedScene
		if demo_scene != null:
			var demo := demo_scene.instantiate()
			add_child(demo)
			var status := demo.get_node_or_null("Status") as Label
			if status == null or status.text == "Map runtime pending":
				failures.append("metroidvania demo did not finish runtime initialization")
			demo.free()
		return failures


## tests/metroidvania_kit/test_map_discovery.gd
class MapDiscoveryCase extends Node:
	const MAP_DEFINITION := "res://addons/metroidvania_kit/map/data/map_definition.gd"
	const MAP_REGION := "res://addons/metroidvania_kit/map/data/map_region.gd"
	const MAP_ROOM := "res://addons/metroidvania_kit/map/data/map_room.gd"
	const MAP_CONNECTION := "res://addons/metroidvania_kit/map/data/map_connection.gd"
	const DISCOVERY := "res://addons/metroidvania_kit/map/discovery/map_discovery.gd"
	const CURRENT_RULE := "res://addons/metroidvania_kit/map/discovery/rules/reveal_current_room.gd"
	const ADJACENT_RULE := "res://addons/metroidvania_kit/map/discovery/rules/reveal_adjacent_rooms.gd"
	const REGION_RULE := "res://addons/metroidvania_kit/map/discovery/rules/reveal_region.gd"
	const RADIUS_RULE := "res://addons/metroidvania_kit/map/discovery/rules/reveal_by_radius.gd"
	const ALL_RULE := "res://addons/metroidvania_kit/map/discovery/rules/reveal_all.gd"


	func run() -> Array[String]:
		var failures: Array[String] = []
		var paths := [MAP_DEFINITION, MAP_REGION, MAP_ROOM, MAP_CONNECTION, DISCOVERY, CURRENT_RULE, ADJACENT_RULE, REGION_RULE, RADIUS_RULE, ALL_RULE]
		var scripts: Array[Script] = []
		for path: String in paths:
			var script := load(path) as Script
			if script == null:
				failures.append("map discovery script is missing: %s" % path)
			else:
				scripts.append(script)
		if not failures.is_empty():
			return failures

		var room_a: Resource = scripts[2].new()
		room_a.set("room_id", &"room_a")
		room_a.set("region_id", &"forest")
		room_a.set("map_position", Vector2i(4, 7))
		room_a.set("map_size", Vector2i(2, 1))
		var room_b: Resource = scripts[2].new()
		room_b.set("room_id", &"room_b")
		room_b.set("region_id", &"forest")
		room_b.set("map_position", Vector2i(8, 7))
		var room_c: Resource = scripts[2].new()
		room_c.set("room_id", &"room_c")
		room_c.set("region_id", &"cave")
		room_c.set("map_position", Vector2i(20, 20))
		var connection: Resource = scripts[3].new()
		connection.set("from_room_id", &"room_a")
		connection.set("to_room_id", &"room_b")
		var forest: Resource = scripts[1].new()
		forest.set("region_id", &"forest")
		var forest_room_ids: Array[StringName] = [&"room_a", &"room_b"]
		forest.set("room_ids", forest_room_ids)
		var definition: Resource = scripts[0].new()
		definition.set("map_id", &"test_map")
		var rooms: Array[Resource] = [room_a, room_b, room_c]
		var regions: Array[Resource] = [forest]
		var connections: Array[Resource] = [connection]
		definition.set("rooms", rooms)
		definition.set("regions", regions)
		definition.set("connections", connections)
		var loaded_room: Resource = definition.call("get_room", &"room_a")
		if loaded_room == null or loaded_room.get("map_position") != Vector2i(4, 7):
			failures.append("authored map coordinates were not preserved independently")

		var discovery: RefCounted = scripts[4].new()
		if int(discovery.call("get_state", &"room_a")) != 0:
			failures.append("unknown room did not start hidden")
		discovery.call("mark_visited", &"room_a")
		discovery.call("mark_discovered", &"room_a")
		if int(discovery.call("get_state", &"room_a")) != 2:
			failures.append("discovery state regressed from visited")
		discovery.call("mark_cleared", &"room_a")
		if int(discovery.call("get_state", &"room_a")) != 3:
			failures.append("room did not transition to cleared")
		if discovery.call("load_dictionary", {"broken": "visited"}):
			failures.append("discovery accepted a non-integer persisted state")

		var fresh: RefCounted = scripts[4].new()
		var current_rule: Resource = scripts[5].new()
		current_rule.call("apply", definition, fresh, &"room_a")
		if int(fresh.call("get_state", &"room_a")) != 2:
			failures.append("current-room rule did not mark the room visited")
		var adjacent_rule: Resource = scripts[6].new()
		adjacent_rule.call("apply", definition, fresh, &"room_a")
		if int(fresh.call("get_state", &"room_b")) != 1:
			failures.append("adjacent-room rule did not discover a neighbor")
		var region_rule: Resource = scripts[7].new()
		region_rule.call("apply", definition, fresh, &"room_a")
		if int(fresh.call("get_state", &"room_b")) < 1 or int(fresh.call("get_state", &"room_c")) != 0:
			failures.append("region rule revealed rooms outside the current region")
		var radius_rule: Resource = scripts[8].new()
		radius_rule.set("radius", 5)
		radius_rule.call("apply", definition, fresh, &"room_a")
		if int(fresh.call("get_state", &"room_b")) < 1 or int(fresh.call("get_state", &"room_c")) != 0:
			failures.append("radius rule ignored authored map coordinates")
		var all_rule: Resource = scripts[9].new()
		all_rule.call("apply", definition, fresh, &"room_a")
		if int(fresh.call("get_state", &"room_c")) != 1:
			failures.append("reveal-all rule did not discover every room")
		return failures


func run() -> Array[String]:
	var failures: Array[String] = []
	failures.append_array(_run_case(ProgressionConditionsCase.new()))
	failures.append_array(_run_case(MetroidvaniaContractCase.new()))
	failures.append_array(_run_case(MapDiscoveryCase.new()))
	return failures


func _run_case(test: Node) -> Array[String]:
	add_child(test)
	var result: Array = test.call("run")
	test.queue_free()
	var failures: Array[String] = []
	failures.assign(result)
	return failures
