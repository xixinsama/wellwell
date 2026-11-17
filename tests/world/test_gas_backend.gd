extends Node

## Explicit gas backend selection on Atmosphere, in headless mode.
##
## The CPU path must bind and simulate a room on its own, a forced GPU without a
## RenderingDevice must degrade to the CPU grid instead of leaving the room
## unbound, and AUTO must keep the historical implicit choice. Toggling the layer
## must park the bound field rather than rebuild it.

const ATMOSPHERE: Script = preload("res://addons/fluid_kit/runtime/gas/atmosphere.gd")
const ROOM_DATA: Script = preload("res://addons/platformer_kit/world/data/room_data.gd")

## The defaults are tuned for 30 Hz, so one call per step is one gas step.
const STEP := 1.0 / 30.0
const STEP_COUNT := 12


func run() -> Array[String]:
	var failures: Array[String] = []
	_assert_cpu_backend(failures)
	_assert_gpu_request_falls_back(failures)
	_assert_auto_backend(failures)
	return failures


func _assert_cpu_backend(failures: Array[String]) -> void:
	var binding := _bind_atmosphere(Atmosphere.Backend.CPU)
	var atmosphere := binding["atmosphere"] as Node2D
	var terrain := binding["terrain"] as Node2D
	if not bool(binding["bound"]):
		failures.append("CPU backend refused to bind a room")
		_cleanup(atmosphere, terrain)
		return
	var state: Dictionary = atmosphere.call("get_debug_state")
	if String(state.get("backend", "none")) != "cpu":
		failures.append("CPU backend reported %s" % String(state.get("backend", "none")))
	if String(state.get("requested_backend", "")) != "cpu":
		failures.append("CPU backend did not report the request")
	if not bool(state.get("ready", false)):
		failures.append("CPU backend did not ready the gas field")
	var before := _density_snapshot(atmosphere)
	if before.is_empty():
		failures.append("CPU backend bound a room without a density grid")
	for _step: int in STEP_COUNT:
		atmosphere.call("_process", STEP)
	var after := _density_snapshot(atmosphere)
	if int(atmosphere.call("get_debug_state").get("steps", 0)) < STEP_COUNT:
		failures.append("CPU backend did not step the gas")
	if _total(after) <= 0.0:
		failures.append("CPU backend stepped an empty gas field")
	if _largest_change(before, after) <= 0.0:
		failures.append("CPU backend did not produce gas density after stepping")
	_assert_toggle_parks_field(atmosphere, failures)
	_cleanup(atmosphere, terrain)


func _assert_toggle_parks_field(atmosphere: Node2D, failures: Array[String]) -> void:
	var steps := int(atmosphere.call("get_debug_state").get("steps", 0))
	var density := _density_snapshot(atmosphere)
	atmosphere.call("set_enabled", false)
	if bool(atmosphere.call("is_enabled")):
		failures.append("set_enabled(false) did not disable the gas layer")
	for _step: int in 4:
		atmosphere.call("_process", STEP)
	if int(atmosphere.call("get_debug_state").get("steps", 0)) != steps:
		failures.append("a disabled gas layer kept stepping")
	atmosphere.call("set_enabled", true)
	if not bool(atmosphere.call("is_enabled")):
		failures.append("the gas layer did not re-enable")
	var restored := _density_snapshot(atmosphere)
	if _largest_change(density, restored) > 0.0:
		failures.append("re-enabling the gas layer rebuilt the field from scratch")
	atmosphere.call("_process", STEP)
	if int(atmosphere.call("get_debug_state").get("steps", 0)) <= steps:
		failures.append("the re-enabled gas layer did not resume stepping")


func _assert_gpu_request_falls_back(failures: Array[String]) -> void:
	var binding := _bind_atmosphere(Atmosphere.Backend.GPU)
	var atmosphere := binding["atmosphere"] as Node2D
	var terrain := binding["terrain"] as Node2D
	if not bool(binding["bound"]):
		failures.append("forced GPU backend refused to bind a room")
		_cleanup(atmosphere, terrain)
		return
	var state: Dictionary = atmosphere.call("get_debug_state")
	var actual := String(state.get("backend", "none"))
	if String(state.get("requested_backend", "")) != "gpu":
		failures.append("forced GPU backend did not report the request")
	if actual == "none" or not bool(state.get("ready", false)):
		failures.append("forced GPU backend left the room unbound")
	elif RenderingServer.get_rendering_device() == null:
		if actual != "cpu":
			failures.append("forced GPU without a RenderingDevice reported %s" % actual)
		if not bool(state.get("fallback", false)):
			failures.append("forced GPU fallback was not reported")
		for _step: int in STEP_COUNT:
			atmosphere.call("_process", STEP)
		if _total(_density_snapshot(atmosphere)) <= 0.0:
			failures.append("the GPU fallback did not simulate any gas")
	elif actual != "gpu" and not bool(state.get("fallback", false)):
		failures.append("forced GPU backend reported %s without a fallback" % actual)
	_cleanup(atmosphere, terrain)


func _assert_auto_backend(failures: Array[String]) -> void:
	var binding := _bind_atmosphere(Atmosphere.Backend.AUTO)
	var atmosphere := binding["atmosphere"] as Node2D
	var terrain := binding["terrain"] as Node2D
	if not bool(binding["bound"]):
		failures.append("AUTO backend refused to bind a room")
		_cleanup(atmosphere, terrain)
		return
	var state: Dictionary = atmosphere.call("get_debug_state")
	if String(state.get("requested_backend", "")) != "auto":
		failures.append("AUTO backend did not report the request")
	var expected := "gpu" if RenderingServer.get_rendering_device() != null else "cpu"
	if String(state.get("backend", "none")) != expected:
		failures.append("AUTO backend reported %s, expected %s" % [state.get("backend"), expected])
	if not bool(state.get("ready", false)):
		failures.append("AUTO backend did not ready the gas field")
	_cleanup(atmosphere, terrain)


## Creates a room-sized terrain root and binds a fresh Atmosphere to it, exactly
## like WorldSession does for a real room.
func _bind_atmosphere(selected_backend: int) -> Dictionary:
	var terrain := _make_terrain_root()
	add_child(terrain)
	var atmosphere := ATMOSPHERE.new() as Node2D
	add_child(atmosphere)
	atmosphere.set("backend", selected_backend)
	# A room starts gas-free on purpose (only GasVent nozzles put gas into it), so
	# seed a density here: these tests are about which backend simulates the field,
	# not about how much gas a new room begins with.
	atmosphere.set("ambient_density", 0.5)
	atmosphere.set("gas_ambient", Vector3(0.3, 0.25, 0.3))
	atmosphere.set("gas_refill", 0.35)
	var room: Resource = ROOM_DATA.new()
	var bound := bool(atmosphere.call("bind_room_with_origin", room, terrain, Vector2i.ZERO))
	return {"atmosphere": atmosphere, "terrain": terrain, "bound": bound}


func _make_terrain_root() -> Node2D:
	var root := Node2D.new()
	var terrain := Node2D.new()
	terrain.name = "Terrain"
	root.add_child(terrain)
	var solid_tiles := TileMapLayer.new()
	solid_tiles.name = "SolidTiles"
	terrain.add_child(solid_tiles)
	return root


func _cleanup(atmosphere: Node2D, terrain: Node2D) -> void:
	if is_instance_valid(atmosphere):
		remove_child(atmosphere)
		atmosphere.free()
	if is_instance_valid(terrain):
		remove_child(terrain)
		terrain.free()


## `get_density_values()` hands out the live grid buffer, which the next step
## writes into; snapshot it so before/after comparisons stay meaningful.
func _density_snapshot(atmosphere: Node2D) -> PackedFloat32Array:
	var values: PackedFloat32Array = atmosphere.call("get_density_values")
	return values.duplicate()


func _total(values: PackedFloat32Array) -> float:
	var total := 0.0
	for value: float in values:
		total += value
	return total


func _largest_change(before: PackedFloat32Array, after: PackedFloat32Array) -> float:
	var largest := 0.0
	for index: int in mini(before.size(), after.size()):
		largest = maxf(largest, absf(after[index] - before[index]))
	return largest
