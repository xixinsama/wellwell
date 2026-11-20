extends Node

## Coverage for the 3D stack projection: the fitted stack stays on screen, slices
## sit above each other, and picking selects the nearest slice. Pure maths.

const CAMERA := preload("res://addons/world_editor/authoring/world/world_stack_camera.gd")


func run() -> Array[String]:
	var failures: Array[String] = []
	_assert_fit_frames_every_slice(failures)
	_assert_stacking_order(failures)
	_assert_picking(failures)
	_assert_pan_moves_the_view(failures)
	_assert_unproject_round_trips(failures)
	_assert_floor_plan_orientation(failures)
	_assert_orbit_and_zoom_clamp(failures)
	return failures


## Room positions must read the same way as in the 2D editor: +y goes down the
## floor plan, z points up. This keeps the two views from being mirrored.
func _assert_floor_plan_orientation(failures: Array[String]) -> void:
	var camera := _make_camera()
	camera.fit([Rect2(0, 0, 2, 2), Rect2(0, 0, 2, 2)])
	var north := camera.project(Vector3(1.0, 0.0, 0.0))
	var south := camera.project(Vector3(1.0, 2.0, 0.0))
	if south.y <= north.y:
		failures.append("world +y does not render below -y: %s vs %s" % [str(south), str(north)])
	var lower := camera.project(Vector3(1.0, 1.0, 0.0))
	var upper := camera.project(Vector3(1.0, 1.0, CAMERA.LAYER_HEIGHT))
	if upper.y >= lower.y:
		failures.append("the layer axis does not point up the screen")
	var east := camera.project(Vector3(2.0, 1.0, 0.0))
	if east.x <= lower.x:
		failures.append("world +x does not render to the right of -x")


func _make_camera() -> WorldStackCamera:
	var camera: WorldStackCamera = CAMERA.new()
	camera.viewport_size = Vector2(800, 600)
	return camera


func _assert_fit_frames_every_slice(failures: Array[String]) -> void:
	var camera := _make_camera()
	var bounds: Array[Rect2] = [Rect2(-1, -1, 3, 2), Rect2(0, 0, 4, 1)]
	if not camera.fit(bounds):
		failures.append("stack camera refused a valid two-layer fit")
		return
	for index: int in range(bounds.size()):
		for point: Vector2 in camera.slab_quad(bounds[index], index):
			if point.x < 0.0 or point.y < 0.0 or point.x > 800.0 or point.y > 600.0:
				failures.append("fitted slice %d leaves the viewport: %s" % [index, str(point)])
				return
	if not camera.fit([Rect2(0, 0, 1, 1)] as Array[Rect2]):
		failures.append("stack camera refused a single-layer fit")
	if camera.fit([] as Array[Rect2]):
		failures.append("stack camera fitted an empty stack")


func _assert_stacking_order(failures: Array[String]) -> void:
	var camera := _make_camera()
	var bounds: Array[Rect2] = [Rect2(0, 0, 2, 2), Rect2(0, 0, 2, 2)]
	camera.fit(bounds)
	var lower := camera.project(Vector3(0.5, 0.5, 0.0))
	var upper := camera.project(Vector3(0.5, 0.5, CAMERA.LAYER_HEIGHT))
	if upper.y >= lower.y:
		failures.append("a higher slice does not sit above a lower one on screen")
	var near_scale := camera.project_scale(Vector3(0.5, 0.5, CAMERA.LAYER_HEIGHT))
	var far_scale := camera.project_scale(Vector3(0.5, 0.5, 0.0))
	if near_scale <= far_scale:
		failures.append("higher slices are not nearer: %.2f vs %.2f" % [near_scale, far_scale])
	if camera.layer_z(0) != 0.0 or not is_equal_approx(camera.layer_z(1), CAMERA.LAYER_HEIGHT):
		failures.append("layer height is not applied per slice")


func _assert_picking(failures: Array[String]) -> void:
	var camera := _make_camera()
	# Two tall, fully overlapping slices: the nearest one must win.
	var overlap: Array[Rect2] = [Rect2(0, 0, 2, 8), Rect2(0, 0, 2, 8)]
	camera.fit(overlap)
	var middle := camera.project(Vector3(1.0, 4.0, 0.0))
	if camera.pick_layer(middle, overlap) != 1:
		failures.append("picking the overlapping centre did not select the nearest slice")
	var first := camera.pick_layer(middle, overlap)
	for _index: int in range(3):
		if camera.pick_layer(middle, overlap) != first:
			failures.append("slice picking is not deterministic")
			break
	# Two slices side by side: each only answers for its own footprint.
	var apart: Array[Rect2] = [Rect2(0, 0, 1, 1), Rect2(8, 0, 1, 1)]
	camera.fit(apart)
	var on_lower := camera.project(Vector3(0.5, 0.5, 0.0))
	var on_upper := camera.project(Vector3(8.5, 0.5, CAMERA.LAYER_HEIGHT))
	if camera.pick_layer(on_lower, apart) != 0:
		failures.append("picking a lone lower slice did not return it")
	if camera.pick_layer(on_upper, apart) != 1:
		failures.append("picking a lone upper slice did not return it")
	if camera.pick_layer(Vector2(-4000, -4000), apart) != -1:
		failures.append("picking outside every slice did not return -1")
	if camera.pick_layer(middle, [] as Array[Rect2]) != -1:
		failures.append("picking an empty stack did not return -1")


func _assert_pan_moves_the_view(failures: Array[String]) -> void:
	var camera := _make_camera()
	var before := camera.project(Vector3(1.0, 1.0, 0.0))
	camera.pan(Vector2(40, -25))
	var after := camera.project(Vector3(1.0, 1.0, 0.0))
	if not after.is_equal_approx(before + Vector2(40, -25)):
		failures.append("panning did not move the view by the drag delta: %s -> %s" % [str(before), str(after)])


func _assert_unproject_round_trips(failures: Array[String]) -> void:
	var camera := _make_camera()
	var bounds: Array[Rect2] = [Rect2(0, 0, 3, 2), Rect2(0, 0, 3, 2)]
	camera.fit(bounds)
	camera.orbit(Vector2(35, 12))
	for layer_index: int in range(bounds.size()):
		for point: Vector2 in [Vector2(0.5, 0.5), Vector2(2.25, 1.4), Vector2(1.0, 1.9)]:
			var screen := camera.project(Vector3(point.x, point.y, camera.layer_z(layer_index)))
			var back: Vector3 = camera.unproject(screen, layer_index)
			if not is_equal_approx(back.x, point.x) or not is_equal_approx(back.y, point.y):
				failures.append(
					"unproject did not invert project on layer %d: %s -> (%.3f, %.3f)"
					% [layer_index, str(point), back.x, back.y]
				)
				return
			if int(back.z) != layer_index:
				failures.append("unproject lost the layer index")
				return


func _assert_orbit_and_zoom_clamp(failures: Array[String]) -> void:
	var camera := _make_camera()
	camera.orbit(Vector2(0, 100000))
	if camera.pitch > CAMERA.PITCH_MAX + 0.0001:
		failures.append("orbit did not clamp the pitch at the top")
	camera.orbit(Vector2(0, -100000))
	if camera.pitch < CAMERA.PITCH_MIN - 0.0001:
		failures.append("orbit did not clamp the pitch at the bottom")
	camera.zoom_by(1000.0)
	if camera.zoom > CAMERA.MAX_ZOOM + 0.0001:
		failures.append("zoom did not clamp at the maximum")
	camera.zoom_by(0.0001)
	if camera.zoom < CAMERA.MIN_ZOOM - 0.0001:
		failures.append("zoom did not clamp at the minimum")
