extends Node

const MARKER_DEFINITION := "res://addons/metroidvania_kit/map/markers/marker_definition.gd"
const MAP_MARKER := "res://addons/metroidvania_kit/map/markers/map_marker.gd"
const MARKER_REGISTRY := "res://addons/metroidvania_kit/map/markers/marker_registry.gd"
const MAP_DISCOVERY := "res://addons/metroidvania_kit/map/discovery/map_discovery.gd"
const MAP_RUNTIME := "res://addons/metroidvania_kit/map/runtime/map_runtime.gd"
const MAP_TRACKER := "res://addons/metroidvania_kit/map/runtime/map_tracker.gd"
const WORLD_STATE := "res://addons/metroidvania_kit/world_state/metroidvania_world_state.gd"
const TRAVEL_POINT := "res://addons/metroidvania_kit/fast_travel/fast_travel_point.gd"
const TRAVEL_REGISTRY := "res://addons/metroidvania_kit/fast_travel/fast_travel_registry.gd"
const MAP_DEFINITION := "res://addons/metroidvania_kit/map/data/map_definition.gd"
const MAP_ROOM := "res://addons/metroidvania_kit/map/data/map_room.gd"
const SAVE_ADAPTER := "res://addons/metroidvania_kit/world_state/metroidvania_save_adapter.gd"
const SAVE_SNAPSHOT := "res://addons/platformer_kit/save/save_snapshot.gd"
const SAVE_CODEC := "res://addons/platformer_kit/save/save_codec.gd"
const PERSISTENCE_BRIDGE := "res://addons/metroidvania_kit/world_state/metroidvania_persistence_bridge.gd"


class FakeSaveManager extends Node:
	signal snapshot_committing(snapshot: RefCounted)
	signal slot_selected(slot: int, snapshot: RefCounted)
	var current_snapshot: RefCounted
	var queue_count := 0
	func queue_commit() -> void: queue_count += 1


func run() -> Array[String]:
	var failures: Array[String] = []
	var paths := [MARKER_DEFINITION, MAP_MARKER, MARKER_REGISTRY, MAP_DISCOVERY, MAP_RUNTIME, MAP_TRACKER, WORLD_STATE, TRAVEL_POINT, TRAVEL_REGISTRY]
	var scripts: Array[Script] = []
	for path: String in paths:
		var script := load(path) as Script
		if script == null:
			failures.append("map runtime script is missing: %s" % path)
		else:
			scripts.append(script)
	if not failures.is_empty():
		return failures

	var marker_definition: Resource = scripts[0].new()
	marker_definition.set("marker_type", &"checkpoint")
	var marker: Resource = scripts[1].new()
	marker.set("marker_id", &"checkpoint:forest:01")
	marker.set("room_id", &"room_a")
	marker.set("definition", marker_definition)
	var registry: RefCounted = scripts[2].new()
	if not registry.call("register_marker", marker):
		failures.append("marker registry rejected a stable marker")
	registry.call("set_discovered", &"checkpoint:forest:01", true)
	registry.call("set_active", &"checkpoint:forest:01", true)
	registry.call("set_completed", &"checkpoint:forest:01", true)
	var marker_state: Dictionary = registry.call("get_state", &"checkpoint:forest:01")
	if not marker_state.get("discovered", false) or not marker_state.get("completed", false):
		failures.append("marker lifecycle state was not retained independently")
	if not registry.call("load_dictionary", {}):
		failures.append("marker registry rejected an empty saved state")
	elif not registry.call("get_state", &"checkpoint:forest:01").is_empty() and bool(registry.call("get_state", &"checkpoint:forest:01").get("discovered", false)):
		failures.append("marker restore retained state absent from the save")
	registry.call("set_discovered", &"checkpoint:forest:01", true)
	registry.call("set_completed", &"checkpoint:forest:01", true)

	var discovery: RefCounted = scripts[3].new()
	discovery.call("mark_visited", &"room_a")
	var saved: Dictionary = {
		"rooms": discovery.call("to_dictionary"),
		"markers": registry.call("to_dictionary"),
	}
	var encoded := JSON.stringify(saved)
	for forbidden: String in ["zoom", "Control.position", "TileMap", "renderer"]:
		if encoded.contains(forbidden):
			failures.append("map persistence contains UI/runtime state: %s" % forbidden)
	var restored_discovery: RefCounted = scripts[3].new()
	if not restored_discovery.call("load_dictionary", saved.rooms):
		failures.append("room discovery state could not be restored")
	var restored_registry: RefCounted = scripts[2].new()
	restored_registry.call("register_marker", marker)
	if not restored_registry.call("load_dictionary", saved.markers):
		failures.append("marker state could not be restored")
	if int(restored_discovery.call("get_state", &"room_a")) != 2:
		failures.append("restored room state changed")
	if not bool(restored_registry.call("get_state", &"checkpoint:forest:01").get("completed", false)):
		failures.append("restored marker state changed")

	var runtime_source := FileAccess.get_file_as_string(MAP_RUNTIME) + FileAccess.get_file_as_string(MAP_TRACKER)
	for forbidden: String in ["extends Control", "CanvasItem", "TextureRect"]:
		if runtime_source.contains(forbidden):
			failures.append("map runtime depends on UI type: %s" % forbidden)

	var world_state: RefCounted = scripts[6].new()
	world_state.call("set_state", &"door:cave:05", {"opened": true})
	if not bool(world_state.call("get_state", &"door:cave:05").get("opened", false)):
		failures.append("world state did not preserve stable-id data")

	var travel_point: Resource = scripts[7].new()
	travel_point.set("travel_id", &"bench:forest:01")
	travel_point.set("room_id", &"room_a")
	travel_point.set("spawn_id", &"bench")
	var travel_registry: RefCounted = scripts[8].new()
	travel_registry.call("register_point", travel_point)
	if travel_registry.call("can_travel", &"bench:forest:01", null):
		failures.append("locked fast-travel point was eligible")
	travel_registry.call("unlock", &"bench:forest:01")
	if not travel_registry.call("can_travel", &"bench:forest:01", null):
		failures.append("unlocked fast-travel point was ineligible")
	var invalid_point: Resource = scripts[7].new()
	invalid_point.set("travel_id", &"broken")
	if travel_registry.call("register_point", invalid_point):
		failures.append("fast travel accepted an empty room or spawn destination")

	var map_definition_script := load(MAP_DEFINITION) as Script
	var map_room_script := load(MAP_ROOM) as Script
	var map_runtime_script := load(MAP_RUNTIME) as Script
	var mapped_room: Resource = map_room_script.new()
	mapped_room.set("room_id", &"map:forest:entry")
	mapped_room.set("world_room_id", &"level_7")
	mapped_room.set("region_id", &"forest")
	var map_definition: Resource = map_definition_script.new()
	var mapped_rooms: Array[Resource] = [mapped_room]
	map_definition.set("rooms", mapped_rooms)
	var mapped_discovery: RefCounted = scripts[3].new()
	var map_runtime: RefCounted = map_runtime_script.new()
	map_runtime.call("configure", map_definition, mapped_discovery)
	if not map_runtime.has_method("enter_world_room"):
		failures.append("map runtime has no world-room mapping entry point")
	elif not map_runtime.call("enter_world_room", &"level_7"):
		failures.append("map runtime could not resolve an independent world-room ID")
	elif StringName(map_runtime.get("current_room_id")) != &"map:forest:entry":
		failures.append("map runtime tracked the world ID instead of the authored map ID")
	var tracker: Node = scripts[5].new()
	tracker.call("configure", map_runtime)
	if not tracker.call("track_room", &"level_7"):
		failures.append("map tracker did not translate a world-room event")
	tracker.free()

	var save_adapter_script := load(SAVE_ADAPTER) as Script
	var snapshot_script := load(SAVE_SNAPSHOT) as Script
	var codec_script := load(SAVE_CODEC) as Script
	if save_adapter_script == null:
		failures.append("metroidvania save adapter is missing")
	else:
		var adapter: RefCounted = save_adapter_script.new()
		var snapshot: RefCounted = snapshot_script.new()
		snapshot.set("slot", 1)
		if not adapter.call("capture", snapshot, null, discovery, registry, world_state, travel_registry):
			failures.append("metroidvania state could not be captured into SaveSnapshot")
		else:
			var codec: RefCounted = codec_script.new()
			var decoded: RefCounted = codec.call("decode", codec.call("encode", snapshot), 1)
			var round_trip_discovery: RefCounted = scripts[3].new()
			var round_trip_registry: RefCounted = scripts[2].new()
			round_trip_registry.call("register_marker", marker)
			var round_trip_world: RefCounted = scripts[6].new()
			var round_trip_travel: RefCounted = scripts[8].new()
			round_trip_travel.call("register_point", travel_point)
			if decoded == null or not adapter.call("restore", decoded, null, round_trip_discovery, round_trip_registry, round_trip_world, round_trip_travel):
				failures.append("metroidvania state did not survive the real save codec")
			elif int(round_trip_discovery.call("get_state", &"room_a")) != 2 or not bool(round_trip_registry.call("get_state", &"checkpoint:forest:01").get("completed", false)):
				failures.append("real save round trip changed discovery or marker state")

			var corrupt_state: Dictionary = decoded.call("get_module_state", &"metroidvania_kit")
			corrupt_state["rooms"] = {"room_b": 2}
			corrupt_state["markers"] = {"missing_marker": {"discovered": true, "active": false, "completed": false}}
			decoded.call("set_module_state", &"metroidvania_kit", corrupt_state)
			if adapter.call("restore", decoded, null, round_trip_discovery, round_trip_registry, round_trip_world, round_trip_travel):
				failures.append("save adapter accepted incompatible marker state")
			elif int(round_trip_discovery.call("get_state", &"room_a")) != 2 or int(round_trip_discovery.call("get_state", &"room_b")) != 0:
				failures.append("failed restore partially mutated discovery state")

	var bridge_script := load(PERSISTENCE_BRIDGE) as Script
	if bridge_script == null:
		failures.append("metroidvania persistence bridge is missing")
	else:
		var manager := FakeSaveManager.new()
		var bridge: Node = bridge_script.new()
		var restore_count := [0]
		if not bridge.has_signal("state_restored"):
			failures.append("persistence bridge does not announce successful restores")
		else:
			bridge.connect("state_restored", func() -> void: restore_count[0] += 1)
		var live_snapshot: RefCounted = snapshot_script.new()
		live_snapshot.set("slot", 1)
		manager.current_snapshot = live_snapshot
		bridge.call("configure", null, discovery, registry, world_state, travel_registry)
		bridge.call("bind_save_manager", manager)
		if restore_count[0] != 1:
			failures.append("persistence bridge did not announce initial empty-state restore")
		discovery.call("mark_visited", &"room_a")
		registry.call("set_discovered", &"checkpoint:forest:01", true)
		registry.call("set_completed", &"checkpoint:forest:01", true)
		world_state.call("set_state", &"door:cave:05", {"opened": true})
		travel_registry.call("unlock", &"bench:forest:01")
		manager.snapshot_committing.emit(live_snapshot)
		if live_snapshot.call("get_module_state", &"metroidvania_kit").is_empty():
			failures.append("persistence bridge did not capture state during snapshot commit")
		discovery.call("load_dictionary", {})
		manager.slot_selected.emit(1, live_snapshot)
		if int(discovery.call("get_state", &"room_a")) != 2:
			failures.append("persistence bridge did not restore state when a slot was selected")
		if restore_count[0] != 2:
			failures.append("persistence bridge did not announce valid slot restore")
		var invalid_bridge_state: Dictionary = live_snapshot.call("get_module_state", &"metroidvania_kit")
		invalid_bridge_state["rooms"] = {"room_b": 2}
		invalid_bridge_state["fog"] = {"cells": "invalid", "chunks": []}
		live_snapshot.call("set_module_state", &"metroidvania_kit", invalid_bridge_state)
		manager.slot_selected.emit(1, live_snapshot)
		if int(discovery.call("get_state", &"room_a")) != 2 or int(discovery.call("get_state", &"room_b")) != 0:
			failures.append("invalid fog persistence partially restored module state")
		if restore_count[0] != 2:
			failures.append("persistence bridge announced a failed restore")
		var empty_snapshot: RefCounted = snapshot_script.new()
		empty_snapshot.set("slot", 2)
		manager.slot_selected.emit(2, empty_snapshot)
		if int(discovery.call("get_state", &"room_a")) != 0:
			failures.append("slot without Metroidvania data retained room discovery")
		if bool(registry.call("get_state", &"checkpoint:forest:01").get("discovered", false)):
			failures.append("slot without Metroidvania data retained marker state")
		if restore_count[0] != 3:
			failures.append("persistence bridge did not announce empty slot reset")
		bridge.free()
		manager.free()
	return failures
