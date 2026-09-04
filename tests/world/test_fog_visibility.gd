extends Node

const FOG_VISIBILITY: Script = preload("res://scripts/world/fog_visibility.gd")
const FOG_OF_WAR: Script = preload("res://scripts/world/fog_of_war.gd")


func run() -> Array[String]:
	var failures: Array[String] = []
	_assert_blocker_is_visible_but_stops_spread(failures)
	_assert_room_spread_crosses_chunk_boundary(failures)
	_assert_room_bounds_stop_spread(failures)
	_assert_room_chunks_configure_cell_bounds(failures)
	_assert_mask_image_matches_current_visibility(failures)
	_assert_cell_ids_are_stable(failures)
	return failures


func _assert_blocker_is_visible_but_stops_spread(failures: Array[String]) -> void:
	var blockers: Dictionary[Vector2i, bool] = {Vector2i(1, 0): true}
	var visibility: RefCounted = FOG_VISIBILITY.new()
	var visible: Dictionary[Vector2i, bool] = visibility.compute_room_visible_cells(
		Vector2i(0, 0),
		Vector2i(0, 0),
		Vector2i(4, 1),
		blockers
	)
	if not visible.has(Vector2i(1, 0)):
		failures.append("blocking cell face was not revealed")
	if visible.has(Vector2i(2, 0)):
		failures.append("fog spread propagated through a blocking cell")


func _assert_room_spread_crosses_chunk_boundary(failures: Array[String]) -> void:
	var visibility: RefCounted = FOG_VISIBILITY.new()
	var visible: Dictionary[Vector2i, bool] = visibility.compute_room_visible_cells(
		Vector2i(39, 11),
		Vector2i(0, 0),
		Vector2i(80, 23),
		{}
	)
	if not visible.has(Vector2i(0, 11)) or not visible.has(Vector2i(79, 11)):
		failures.append("room fog did not spread across a two-chunk room")


func _assert_room_bounds_stop_spread(failures: Array[String]) -> void:
	var visibility: RefCounted = FOG_VISIBILITY.new()
	var visible: Dictionary[Vector2i, bool] = visibility.compute_room_visible_cells(
		Vector2i(0, 0),
		Vector2i(0, 0),
		Vector2i(2, 2),
		{}
	)
	if visible.has(Vector2i(-1, 0)) or visible.has(Vector2i(2, 0)):
		failures.append("room fog spread outside the active room")


func _assert_room_chunks_configure_cell_bounds(failures: Array[String]) -> void:
	var fog: Node2D = FOG_OF_WAR.new() as Node2D
	fog.cell_size = Vector2i(8, 8)
	fog.chunk_size_pixels = Vector2i(320, 180)
	fog.set_room_chunks(Vector2i(2, 1), Vector2i(3, 2))
	if fog.map_origin_cell != Vector2i(80, 23):
		failures.append("room chunk origin did not convert to fog cells")
	if fog.map_size_cells != Vector2i(120, 46):
		failures.append("room chunk size did not convert to fog cells")
	fog.free()


func _assert_mask_image_matches_current_visibility(failures: Array[String]) -> void:
	var fog: Node2D = FOG_OF_WAR.new() as Node2D
	fog.map_origin_cell = Vector2i(0, 0)
	fog.map_size_cells = Vector2i(4, 1)
	fog.cell_size = Vector2i(8, 8)
	fog.reveal_from_cell(Vector2i(0, 0), {Vector2i(1, 0): true})

	var mask: Image = fog.get_mask_image()
	if mask == null:
		failures.append("fog mask image was not created")
	elif mask.get_size() != Vector2i(32, 8):
		failures.append("fog mask image did not match room pixel size")
	elif mask.get_pixel(4, 4).a != 0.0:
		failures.append("visible fog mask pixel was not transparent")
	elif mask.get_pixel(12, 4).a != 0.0:
		failures.append("blocking fog mask pixel was not transparent")
	elif mask.get_pixel(20, 4).a <= 0.9:
		failures.append("unreached fog mask pixel was not opaque")
	if fog.get_mask_texture() == null:
		failures.append("fog mask texture was not created")
	fog.free()


func _assert_cell_ids_are_stable(failures: Array[String]) -> void:
	var fog: Node2D = FOG_OF_WAR.new() as Node2D
	fog.level_id = "level_01"
	if fog.cell_to_id(Vector2i(12, -4)) != "level_01:12,-4":
		failures.append("fog cell id format changed")
	var saved_ids: Array[String] = ["level_01:12,-4", "other:1,1", "broken"]
	fog.load_explored_cells(saved_ids)
	if not fog.is_cell_explored(Vector2i(12, -4)):
		failures.append("saved fog cell id was not loaded")
	if fog.is_cell_explored(Vector2i(1, 1)):
		failures.append("foreign level cell id was loaded")
	fog.free()
