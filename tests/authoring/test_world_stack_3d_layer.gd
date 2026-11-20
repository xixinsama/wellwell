extends Node

## Headless contract test for WorldStack3DLayer — the World editor's stacked
## (3D) world view.
##
## Everything here is the non-painting half of the layer: the payload plumbing,
## framing, slice picking, the drag/click routing and the cursor readout. `_draw`
## is deliberately never called (it cannot run outside a draw pass); the painted
## result is verified by rendering the layer into a SubViewport, not from here.

const LAYER_PATH := "res://addons/world_editor/world_stack_3d_layer.gd"
const VIEW_SIZE := Vector2(960.0, 600.0)
const SLAB_THICKNESS := 0.12
## Slab corners may sit exactly on the edge, so allow half a pixel of slack.
const CORNER_SLACK := 0.5
const SCAN_STEP := 6.0
const READOUT_TOLERANCE := 0.01
## Transition budget the author asked for, in seconds.
const GIZMO_LENGTH := 30.0
## `unproject` and `project` must invert each other for the readout to be honest.
const PROJECTION_TOLERANCE := 0.1

const WORLD_A := "loop"
const WORLD_B := "tide"
const WORLD_C := "lantern"


func run() -> Array[String]:
	var failures: Array[String] = []
	var script := load(LAYER_PATH) as Script
	if script == null or not script.can_instantiate():
		return ["world stack 3D layer could not be loaded"]
	var probe := script.new() as Control
	if probe == null:
		return ["world stack 3D layer is not a Control"]
	_assert_api(probe, failures)
	probe.free()
	if not failures.is_empty():
		return failures
	_assert_empty_payload(script, failures)
	_assert_layer_count(script, failures)
	_assert_focus_frames_stack(script, failures)
	_assert_world_at(script, failures)
	_assert_pan_routing(script, failures)
	_assert_orbit_and_click(script, failures)
	_assert_axis_gizmo(script, failures)
	_assert_cursor_readout(script, failures)
	_assert_readout_fallback(script, failures)
	return failures


func _assert_api(layer: Control, failures: Array[String]) -> void:
	var required: Array[StringName] = [
		&"set_stack", &"focus_stack", &"get_camera", &"get_layer_count", &"world_at",
		&"get_cursor_readout",
	]
	for method: StringName in required:
		if not layer.has_method(method):
			failures.append("world stack 3D layer is missing %s" % method)
	if not layer.has_signal("world_picked"):
		failures.append("world stack 3D layer is missing the world_picked signal")
	var camera: Object = layer.call("get_camera")
	if camera == null:
		failures.append("world stack 3D layer has no camera")
		return
	for method: StringName in [&"orbit", &"pan", &"zoom_by", &"unproject"]:
		if not camera.has_method(method):
			failures.append("WorldStackCamera is missing %s" % method)


func _assert_empty_payload(script: Script, failures: Array[String]) -> void:
	var layer := _new_layer(script)
	layer.call("set_stack", {})
	if int(layer.call("get_layer_count")) != 0:
		failures.append("an empty payload produced layers")
	layer.call("set_stack", {"current_world_id": "", "layers": [], "links": [], "dangling_count": 0})
	if int(layer.call("get_layer_count")) != 0:
		failures.append("a payload without layers produced layers")
	if String(layer.call("world_at", VIEW_SIZE * 0.5)) != "":
		failures.append("an empty stack picked a world")
	var readout: Dictionary = layer.call("get_cursor_readout")
	if not readout.is_empty():
		failures.append("an empty stack produced a cursor readout: %s" % readout)
	layer.free()


func _assert_layer_count(script: Script, failures: Array[String]) -> void:
	var layer := _new_layer(script)
	layer.call("set_stack", _payload(3))
	if int(layer.call("get_layer_count")) != 3:
		failures.append("three-layer payload reported %d layers" % int(layer.call("get_layer_count")))
	layer.call("set_stack", _payload(1))
	if int(layer.call("get_layer_count")) != 1:
		failures.append("single-layer payload reported %d layers" % int(layer.call("get_layer_count")))
	layer.call("set_stack", {
		"current_world_id": WORLD_A,
		"layers": [
			{"index": 0, "world_id": "", "bounds": Rect2(0.0, 0.0, 1.0, 1.0)},
			{"index": 1, "world_id": WORLD_B, "bounds": Rect2(0.0, 0.0, 1.0, 1.0)},
			"not a layer",
		],
		"links": [],
		"dangling_count": 0,
	})
	if int(layer.call("get_layer_count")) != 1:
		failures.append("malformed layer entries were counted as slices")
	layer.free()


func _assert_focus_frames_stack(script: Script, failures: Array[String]) -> void:
	var layer := _new_layer(script)
	layer.call("set_stack", _payload(3))
	layer.call("focus_stack")
	var camera: Object = layer.call("get_camera")
	if camera == null:
		failures.append("focus_stack left the layer without a camera")
		layer.free()
		return
	var bounds_list := _payload_bounds(3)
	var view := Rect2(Vector2.ZERO, VIEW_SIZE)
	for index: int in range(bounds_list.size()):
		var bounds: Rect2 = bounds_list[index]
		var z := float(camera.call("layer_z", index))
		var corners: Array[Vector3] = [
			Vector3(bounds.position.x, bounds.position.y, z),
			Vector3(bounds.end.x, bounds.position.y, z),
			Vector3(bounds.end.x, bounds.end.y, z),
			Vector3(bounds.position.x, bounds.end.y, z),
			Vector3(bounds.position.x, bounds.position.y, z - SLAB_THICKNESS),
			Vector3(bounds.end.x, bounds.position.y, z - SLAB_THICKNESS),
			Vector3(bounds.end.x, bounds.end.y, z - SLAB_THICKNESS),
			Vector3(bounds.position.x, bounds.end.y, z - SLAB_THICKNESS),
		]
		for corner: Vector3 in corners:
			var screen: Vector2 = camera.call("project", corner)
			if not view.grow(CORNER_SLACK).has_point(screen):
				failures.append(
					"focus_stack left layer %d outside the control: corner %s projected to %s"
					% [index, corner, screen]
				)
				layer.free()
				return
	layer.free()


func _assert_world_at(script: Script, failures: Array[String]) -> void:
	var layer := _new_layer(script)
	layer.call("set_stack", _payload(3))
	layer.call("focus_stack")
	var camera: Object = layer.call("get_camera")
	if camera == null:
		failures.append("world_at has no camera to project with")
		layer.free()
		return
	var quads := _layer_quads(camera, 3)

	var overlap := _find_point(quads, 2)
	if not bool(overlap["found"]):
		failures.append("could not build a point inside two overlapping slices")
	else:
		var overlap_layers: Array = overlap["layers"]
		var nearest: int = overlap_layers.max()
		var expected := _world_id(nearest)
		var actual := String(layer.call("world_at", overlap["point"]))
		if actual != expected:
			failures.append(
				"world_at on an overlapping point returned %s, expected the nearest slice %s"
				% [actual, expected]
			)
		var farthest: int = overlap_layers.min()
		if farthest != nearest and _world_id(farthest) == expected:
			failures.append("overlap fixture used the same world on both slices")
		for repeat: int in range(3):
			if String(layer.call("world_at", overlap["point"])) != expected:
				failures.append("world_at was not deterministic on an overlapping point (call %d)" % (repeat + 2))
				break
		layer.call("set_stack", _payload(3))
		layer.call("focus_stack")
		if String(layer.call("world_at", overlap["point"])) != expected:
			failures.append("world_at changed after re-sending the same payload")

	var single := _find_point(quads, 1)
	if not bool(single["found"]):
		failures.append("could not build a point inside exactly one slice")
	else:
		var single_layers: Array = single["layers"]
		var expected_single := _world_id(int(single_layers[0]))
		var actual_single := String(layer.call("world_at", single["point"]))
		if actual_single != expected_single:
			failures.append(
				"world_at on a single-slice point returned %s, expected %s"
				% [actual_single, expected_single]
			)
		for repeat: int in range(3):
			if String(layer.call("world_at", single["point"])) != expected_single:
				failures.append("world_at was not deterministic on a single-slice point")
				break

	var outside := _find_outside_point(quads)
	if not bool(outside["found"]):
		failures.append("could not build a point outside every slice")
	elif String(layer.call("world_at", outside["point"])) != "":
		failures.append(
			"world_at picked %s outside every slice"
			% String(layer.call("world_at", outside["point"]))
		)
	for point: Vector2 in [Vector2(-5000.0, -5000.0), Vector2(5000.0, 5000.0)]:
		if String(layer.call("world_at", point)) != "":
			failures.append("world_at picked a world far outside the stack at %s" % point)
	layer.free()


## Middle drag, right drag and Shift+left drag all pan; none of them may pick.
func _assert_pan_routing(script: Script, failures: Array[String]) -> void:
	var cases: Array[Dictionary] = [
		{"button": MOUSE_BUTTON_MIDDLE, "shift": false, "drag": Vector2(37.0, -21.0), "label": "middle drag"},
		{"button": MOUSE_BUTTON_RIGHT, "shift": false, "drag": Vector2(-24.0, 12.0), "label": "right drag"},
		{"button": MOUSE_BUTTON_LEFT, "shift": true, "drag": Vector2(18.0, 26.0), "label": "Shift+left drag"},
	]
	for case: Dictionary in cases:
		var layer := _new_layer(script)
		layer.call("set_stack", _payload(3))
		layer.call("focus_stack")
		var camera: Object = layer.call("get_camera")
		var picked := _record_picks(layer)
		var start := Vector2(420.0, 300.0)
		var drag: Vector2 = case["drag"]
		var before_offset: Vector2 = camera.get("offset")
		var before_point: Vector2 = camera.call("project", Vector3(0.0, 0.0, 0.0))
		var before_yaw := float(camera.get("yaw"))
		var before_pitch := float(camera.get("pitch"))
		_press(layer, case["button"], start, bool(case["shift"]))
		_motion(layer, start + drag, drag)
		_release(layer, case["button"], start + drag, bool(case["shift"]))
		var after_offset: Vector2 = camera.get("offset")
		var after_point: Vector2 = camera.call("project", Vector3(0.0, 0.0, 0.0))
		if not after_offset.is_equal_approx(before_offset + drag):
			failures.append(
				"%s panned by %s instead of %s" % [case["label"], after_offset - before_offset, drag]
			)
		if not after_point.is_equal_approx(before_point + drag):
			failures.append(
				"%s did not move the projection by the drag delta (moved %s)"
				% [case["label"], after_point - before_point]
			)
		if not is_equal_approx(float(camera.get("yaw")), before_yaw):
			failures.append("%s orbited the yaw" % case["label"])
		if not is_equal_approx(float(camera.get("pitch")), before_pitch):
			failures.append("%s orbited the pitch" % case["label"])
		if not picked.is_empty():
			failures.append("%s emitted world_picked (%s)" % [case["label"], picked])
		layer.free()


## A left drag orbits and never picks; a click picks exactly once.
func _assert_orbit_and_click(script: Script, failures: Array[String]) -> void:
	var layer := _new_layer(script)
	layer.call("set_stack", _payload(3))
	layer.call("focus_stack")
	var camera: Object = layer.call("get_camera")
	var picked := _record_picks(layer)

	var before_offset: Vector2 = camera.get("offset")
	var before_yaw := float(camera.get("yaw"))
	_press(layer, MOUSE_BUTTON_LEFT, Vector2(420.0, 300.0))
	_motion(layer, Vector2(450.0, 308.0), Vector2(30.0, 8.0))
	_release(layer, MOUSE_BUTTON_LEFT, Vector2(450.0, 308.0))
	if is_equal_approx(float(camera.get("yaw")), before_yaw):
		failures.append("a left drag did not orbit")
	if not (camera.get("offset") as Vector2).is_equal_approx(before_offset):
		failures.append("a left drag panned the view as well as orbiting")
	if not picked.is_empty():
		failures.append("an orbit drag emitted world_picked (%s)" % picked)

	layer.call("focus_stack")
	var target := _find_layer_point(camera, _layer_quads(camera, 3), 2)
	if not bool(target["found"]):
		failures.append("could not build a click target on layer 2")
		layer.free()
		return
	var point: Vector2 = target["screen"]

	# A click picks the nearest slice immediately; a drag never picks.
	_press(layer, MOUSE_BUTTON_LEFT, point)
	_release(layer, MOUSE_BUTTON_LEFT, point)
	if picked.size() != 1:
		failures.append("a click emitted %d world_picked signals, expected 1" % picked.size())
	elif String(picked[0]) != WORLD_C:
		failures.append("a click picked %s, expected the nearest slice %s" % [picked[0], WORLD_C])

	# A 3 px wobble is still a click; 6 px is a drag and must not pick.
	_press(layer, MOUSE_BUTTON_LEFT, point)
	_motion(layer, point + Vector2(3.0, 0.0), Vector2(3.0, 0.0))
	_release(layer, MOUSE_BUTTON_LEFT, point + Vector2(3.0, 0.0))
	if picked.size() != 2:
		failures.append("a 3 px click did not pick (signals=%d)" % picked.size())
	layer.call("focus_stack")
	_press(layer, MOUSE_BUTTON_LEFT, point)
	_motion(layer, point + Vector2(6.0, 0.0), Vector2(6.0, 0.0))
	_release(layer, MOUSE_BUTTON_LEFT, point + Vector2(6.0, 0.0))
	if picked.size() != 2:
		failures.append("a 6 px drag picked a world (signals=%d)" % picked.size())

	var outside := _find_outside_point(_layer_quads(camera, 3))
	if bool(outside["found"]):
		_press(layer, MOUSE_BUTTON_LEFT, outside["point"])
		_release(layer, MOUSE_BUTTON_LEFT, outside["point"])
		if picked.size() != 2:
			failures.append("a click outside every slice emitted world_picked")
	layer.free()


## The viewport carries its own axis gizmo: X right, Y down the floor plan (the
## chunk grid's direction, so rooms sit where the 2D view puts them) and Z up the
## stack. It only reports geometry, which is what this asserts.
func _assert_axis_gizmo(script: Script, failures: Array[String]) -> void:
	var layer := _new_layer(script)
	layer.call("set_stack", _payload(3))
	layer.call("focus_stack")
	var gizmo: Dictionary = layer.call("get_axis_gizmo")
	var axes: Array = gizmo.get("axes", [])
	if axes.size() != 3:
		failures.append("the axis gizmo did not report three axes: %d" % axes.size())
		layer.free()
		return
	var origin: Vector2 = gizmo.get("origin", Vector2.ZERO)
	var by_name: Dictionary = {}
	for axis: Dictionary in axes:
		by_name[String(axis.get("name", ""))] = axis
	for axis_name: String in ["X", "Y", "Z"]:
		if not by_name.has(axis_name):
			failures.append("the axis gizmo is missing the %s axis" % axis_name)
			layer.free()
			return
	var x_axis: Dictionary = by_name["X"]
	var y_axis: Dictionary = by_name["Y"]
	var z_axis: Dictionary = by_name["Z"]
	if (x_axis.get("tip", origin) as Vector2).x <= origin.x:
		failures.append("the X axis does not point right")
	if (y_axis.get("tip", origin) as Vector2).y <= origin.y:
		failures.append("the Y axis does not point down the floor plan")
	if (z_axis.get("tip", origin) as Vector2).y >= origin.y:
		failures.append("the Z axis does not point up the stack")
	var colors: Dictionary = {}
	for axis: Dictionary in axes:
		colors[(axis.get("color", Color.BLACK) as Color).to_html()] = true
	if colors.size() != 3:
		failures.append("the axis gizmo reuses a colour between axes")
	if absf(origin.distance_to((x_axis.get("tip", origin) as Vector2)) - GIZMO_LENGTH) > 0.01:
		failures.append("the gizmo axes are not the configured length")
	if origin.x < 0.0 or origin.x > layer.size.x or origin.y < 0.0 or origin.y > layer.size.y:
		failures.append("the gizmo origin is outside the viewport: %s" % str(origin))
	layer.free()


## The readout must invert the projection on the slice the pointer is over.
func _assert_cursor_readout(script: Script, failures: Array[String]) -> void:
	var layer := _new_layer(script)
	layer.call("set_stack", _payload(3))
	layer.call("focus_stack")
	var camera: Object = layer.call("get_camera")
	var quads := _layer_quads(camera, 3)
	for index: int in range(3):
		var target := _find_layer_point(camera, quads, index)
		if not bool(target["found"]):
			failures.append("could not build an exclusive pointer position on layer %d" % index)
			continue
		var screen: Vector2 = target["screen"]
		var world_point: Vector2 = target["point"]
		_motion(layer, screen, Vector2.ZERO)
		var readout: Dictionary = layer.call("get_cursor_readout")
		for key: String in ["x", "y", "z", "layer_index", "world_id"]:
			if not readout.has(key):
				failures.append("cursor readout is missing %s" % key)
		if readout.is_empty():
			failures.append("cursor readout was empty over layer %d" % index)
			continue
		if int(readout.get("layer_index", -1)) != index:
			failures.append(
				"readout layer_index was %s over layer %d" % [readout.get("layer_index"), index]
			)
		if int(readout.get("z", -1)) != index:
			failures.append("readout z was %s over layer %d" % [readout.get("z"), index])
		if absf(float(readout.get("x", 0.0)) - world_point.x) > READOUT_TOLERANCE:
			failures.append(
				"readout x was %.3f at world x %.3f on layer %d"
				% [float(readout.get("x", 0.0)), world_point.x, index]
			)
		if absf(float(readout.get("y", 0.0)) - world_point.y) > READOUT_TOLERANCE:
			failures.append(
				"readout y was %.3f at world y %.3f on layer %d"
				% [float(readout.get("y", 0.0)), world_point.y, index]
			)
		if String(readout.get("world_id", "")) != _world_id(index):
			failures.append(
				"readout world_id was %s over layer %d" % [readout.get("world_id"), index]
			)
		# The pointer must project back to where it is: readout x/y are the
		# inverse of the projection, not an independent guess.
		var layer_z := float(camera.call("layer_z", index))
		var reprojected: Vector2 = camera.call(
			"project", Vector3(float(readout.get("x", 0.0)), float(readout.get("y", 0.0)), layer_z)
		)
		if reprojected.distance_to(screen) > PROJECTION_TOLERANCE:
			failures.append(
				"readout on layer %d projected back to %s instead of %s"
				% [index, reprojected, screen]
			)
		if index == 1:
			var text := String(layer.call("_readout_text", readout))
			if not text.begins_with("x ") or not text.contains("   y ") or not text.contains("   z 1"):
				failures.append("readout text has the wrong shape: %s" % text)
	layer.free()


## Off the stack the readout keeps tracking the pointer on layer 0.
func _assert_readout_fallback(script: Script, failures: Array[String]) -> void:
	var layer := _new_layer(script)
	layer.call("set_stack", _payload(3))
	layer.call("focus_stack")
	var camera: Object = layer.call("get_camera")
	var quads := _layer_quads(camera, 3)
	var first := _find_outside_point(quads)
	if not bool(first["found"]):
		failures.append("could not build a point outside every slice for the readout")
		layer.free()
		return
	_motion(layer, first["point"], Vector2.ZERO)
	var readout: Dictionary = layer.call("get_cursor_readout")
	if readout.is_empty():
		failures.append("readout was empty off the stack")
		layer.free()
		return
	if int(readout.get("layer_index", -1)) != 0 or int(readout.get("z", -1)) != 0:
		failures.append(
			"readout off the stack did not fall back to layer 0: %s" % readout
		)
	if String(readout.get("world_id", "")) != WORLD_A:
		failures.append(
			"readout off the stack reported world %s instead of the edited world %s"
			% [readout.get("world_id"), WORLD_A]
		)
	var reprojected: Vector2 = camera.call(
		"project",
		Vector3(float(readout.get("x", 0.0)), float(readout.get("y", 0.0)), float(camera.call("layer_z", 0)))
	)
	if reprojected.distance_to(first["point"]) > PROJECTION_TOLERANCE:
		failures.append(
			"fallback readout does not sit on layer 0's plane: %s vs pointer %s"
			% [reprojected, first["point"]]
		)

	# It tracks the pointer instead of freezing on the last slice value.
	var second: Vector2 = first["point"] + Vector2(0.0, -80.0)
	if Rect2(Vector2.ZERO, VIEW_SIZE).has_point(second) \
			and _containing_layers(quads, second).is_empty():
		_motion(layer, second, Vector2.ZERO)
		var moved: Dictionary = layer.call("get_cursor_readout")
		if is_equal_approx(float(moved.get("x", 0.0)), float(readout.get("x", 0.0))) \
				and is_equal_approx(float(moved.get("y", 0.0)), float(readout.get("y", 0.0))):
			failures.append("fallback readout froze instead of tracking the pointer")
	layer.free()


# --- Fixtures ----------------------------------------------------------------

func _new_layer(script: Script) -> Control:
	var layer := script.new() as Control
	layer.size = VIEW_SIZE
	return layer


func _payload_bounds(layer_count: int) -> Array[Rect2]:
	var bounds: Array[Rect2] = []
	for layer: Dictionary in _layer_specs(layer_count):
		bounds.append(layer["bounds"] as Rect2)
	return bounds


func _layer_quads(camera: Object, layer_count: int) -> Array[PackedVector2Array]:
	var quads: Array[PackedVector2Array] = []
	var bounds_list := _payload_bounds(layer_count)
	for index: int in range(bounds_list.size()):
		quads.append(camera.call("slab_quad", bounds_list[index], index))
	return quads


func _world_id(layer_index: int) -> String:
	match layer_index:
		0:
			return WORLD_A
		1:
			return WORLD_B
		2:
			return WORLD_C
	return ""


func _payload(layer_count: int) -> Dictionary:
	return {
		"current_world_id": WORLD_A,
		"layers": _layer_specs(layer_count),
		"links": [
			{
				"kind": "portal", "paired": true,
				"from_layer": 0, "from_pos": Vector2(0.5, 0.18),
				"to_layer": 0, "to_pos": Vector2(0.5, 0.86),
			},
			{
				"kind": "shuttle", "paired": true,
				"from_layer": 0, "from_pos": Vector2(0.86, 0.5),
				"to_layer": 1, "to_pos": Vector2(0.12, 0.5),
			},
			{
				"kind": "shuttle", "paired": false,
				"from_layer": 2, "from_pos": Vector2(0.75, 0.7),
				"to_layer": 9, "to_pos": Vector2(1.0, 1.0),
			},
		],
		"dangling_count": 1,
	}


## Three slices with deliberately overlapping footprints, so picking has to
## choose between them.
func _layer_specs(layer_count: int) -> Array:
	var specs: Array = [
		{
			"index": 0,
			"world_id": WORLD_A,
			"name": "回环水窖",
			"color": Color.from_hsv(0.47, 1.0, 0.95),
			"bounds": Rect2(-1.0, -1.0, 4.0, 3.0),
			"rooms": [
				{"id": "loop_entry", "rect": Rect2(0.0, 0.0, 1.0, 1.0)},
				{"id": "loop_gallery", "rect": Rect2(0.0, -1.0, 2.0, 1.0)},
			],
			"doors": [
				{"id": "entry_up", "pos": Vector2(0.5, 0.18), "kind": 0},
				{"id": "relay_right", "pos": Vector2(0.86, 0.5), "kind": 1},
			],
		},
		{
			"index": 1,
			"world_id": WORLD_B,
			"name": "潮汐下层",
			"color": Color.from_hsv(0.72, 1.0, 0.95),
			"bounds": Rect2(-0.5, -1.5, 5.0, 3.0),
			"rooms": [
				{"id": "tide_hall", "rect": Rect2(0.0, 0.0, 2.0, 1.0)},
			],
			"doors": [
				{"id": "hall_left", "pos": Vector2(0.12, 0.5), "kind": 1},
			],
		},
		{
			"index": 2,
			"world_id": WORLD_C,
			"name": "灯影实验场",
			"color": Color.from_hsv(0.1, 1.0, 0.95),
			"bounds": Rect2(0.5, -0.5, 2.5, 2.0),
			"rooms": [
				{"id": "lamp_atrium", "rect": Rect2(0.0, 0.0, 1.0, 2.0)},
			],
			"doors": [
				{"id": "orphan", "pos": Vector2(0.25, 0.2), "kind": 1},
			],
		},
	]
	var result: Array = []
	for index: int in range(mini(layer_count, specs.size())):
		result.append(specs[index])
	return result


# --- Sampling helpers --------------------------------------------------------

func _find_point(quads: Array[PackedVector2Array], wanted_layers: int) -> Dictionary:
	var y := 0.0
	while y <= VIEW_SIZE.y:
		var x := 0.0
		while x <= VIEW_SIZE.x:
			var candidate := Vector2(x, y)
			var layers := _containing_layers(quads, candidate)
			if wanted_layers <= 1:
				if layers.size() == 1:
					return {"found": true, "point": candidate, "layers": layers}
			elif layers.size() >= wanted_layers:
				return {"found": true, "point": candidate, "layers": layers}
			x += SCAN_STEP
		y += SCAN_STEP
	return {"found": false, "point": Vector2.ZERO, "layers": []}


func _find_outside_point(quads: Array[PackedVector2Array]) -> Dictionary:
	var candidates: Array[Vector2] = [
		Vector2(1.0, 1.0),
		Vector2(VIEW_SIZE.x - 2.0, 1.0),
		Vector2(1.0, VIEW_SIZE.y - 2.0),
		Vector2(VIEW_SIZE.x - 2.0, VIEW_SIZE.y - 2.0),
		Vector2(VIEW_SIZE.x * 0.5, 1.0),
		Vector2(VIEW_SIZE.x * 0.5, VIEW_SIZE.y - 2.0),
		Vector2(1.0, VIEW_SIZE.y * 0.5),
		Vector2(VIEW_SIZE.x - 2.0, VIEW_SIZE.y * 0.5),
	]
	for candidate: Vector2 in candidates:
		if _containing_layers(quads, candidate).is_empty():
			return {"found": true, "point": candidate, "layers": []}
	return {"found": false, "point": Vector2.ZERO, "layers": []}


## A world point on [param layer_index] whose projected pixel is only over that
## slice, so the pointer has an unambiguous answer there.
func _find_layer_point(
	camera: Object, quads: Array[PackedVector2Array], layer_index: int
) -> Dictionary:
	var bounds := _payload_bounds(3)[layer_index]
	var view := Rect2(Vector2.ZERO, VIEW_SIZE)
	var z := float(camera.call("layer_z", layer_index))
	var step := 0.25
	var y := bounds.position.y + 0.05
	while y <= bounds.end.y - 0.05:
		var x := bounds.position.x + 0.05
		while x <= bounds.end.x - 0.05:
			var screen: Vector2 = camera.call("project", Vector3(x, y, z))
			if view.has_point(screen) and _topmost_layer(quads, screen) == layer_index:
				return {"found": true, "point": Vector2(x, y), "screen": screen}
			x += step
		y += step
	return {"found": false, "point": Vector2.ZERO, "screen": Vector2.ZERO}


func _topmost_layer(quads: Array[PackedVector2Array], point: Vector2) -> int:
	var layers := _containing_layers(quads, point)
	return -1 if layers.is_empty() else int(layers.max())


func _containing_layers(quads: Array[PackedVector2Array], point: Vector2) -> Array:
	var layers: Array = []
	for index: int in range(quads.size()):
		if WorldStackCamera.geometry_contains(quads[index], point):
			layers.append(index)
	return layers


# --- Input helpers -----------------------------------------------------------

func _record_picks(layer: Control) -> Array:
	var picked: Array = []
	layer.connect("world_picked", func(world_id: String) -> void: picked.append(world_id))
	return picked


func _press(layer: Control, button: MouseButton, position: Vector2, shift: bool = false) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = true
	event.position = position
	event.shift_pressed = shift
	layer.call("_gui_input", event)


func _release(layer: Control, button: MouseButton, position: Vector2, shift: bool = false) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = false
	event.position = position
	event.shift_pressed = shift
	layer.call("_gui_input", event)


func _motion(layer: Control, position: Vector2, relative: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = position
	event.relative = relative
	layer.call("_gui_input", event)
