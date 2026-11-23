extends Node

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
