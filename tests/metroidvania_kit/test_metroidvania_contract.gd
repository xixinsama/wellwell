extends Node

const MANIFEST := "res://addons/metroidvania_kit/plugin.cfg"
const DEMO := "res://examples/metroidvania_demo/metroidvania_demo.tscn"
const MOVEMENT_LAB := "res://examples/movement_lab/movement_lab.tscn"
const FOG := "res://addons/metroidvania_kit/map/discovery/fog_of_war.gd"
const FOG_VISIBILITY := "res://addons/metroidvania_kit/map/discovery/fog_visibility.gd"
const MAP_VIEW := "res://addons/metroidvania_kit/map/ui/map_view.tscn"
const MINIMAP := "res://addons/metroidvania_kit/map/ui/minimap.tscn"
const MAP_RENDERER := "res://addons/metroidvania_kit/map/ui/map_renderer.gd"
const MAIN_MAP := "res://game/data/maps/main_map.tres"
const MAIN_SCRIPT := "res://scripts/app/main.gd"


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
	if load(MAIN_MAP) as Resource == null:
		failures.append("reference game has no authored Metroidvania map definition")
	var main_source := FileAccess.get_file_as_string(MAIN_SCRIPT)
	if main_source.contains("configure(null, null, null, null, null, fog)"):
		failures.append("reference game persistence bridge only composes fog state")
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
