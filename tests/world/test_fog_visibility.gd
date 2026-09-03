extends Node

const FOG_VISIBILITY: Script = preload("res://scripts/world/fog_visibility.gd")
const FOG_OF_WAR: Script = preload("res://scripts/world/fog_of_war.gd")


func run() -> Array[String]:
	var failures: Array[String] = []
	_assert_wall_blocks_behind_it(failures)
	_assert_target_wall_face_is_visible(failures)
	_assert_exploration_can_accumulate(failures)
	_assert_cell_ids_are_stable(failures)
	return failures


func _assert_wall_blocks_behind_it(failures: Array[String]) -> void:
	var blockers: Dictionary[Vector2i, bool] = {Vector2i(1, 0): true}
	var visibility: RefCounted = FOG_VISIBILITY.new()
	if visibility.has_line_of_sight(Vector2i(0, 0), Vector2i(2, 0), blockers):
		failures.append("line of sight passed through a blocker")


func _assert_target_wall_face_is_visible(failures: Array[String]) -> void:
	var blockers: Dictionary[Vector2i, bool] = {Vector2i(1, 0): true}
	var visibility: RefCounted = FOG_VISIBILITY.new()
	if not visibility.has_line_of_sight(Vector2i(0, 0), Vector2i(1, 0), blockers):
		failures.append("target blocker face was hidden")


func _assert_exploration_can_accumulate(failures: Array[String]) -> void:
	var blockers: Dictionary[Vector2i, bool] = {Vector2i(1, 0): true}
	var visibility: RefCounted = FOG_VISIBILITY.new()
	var left: Dictionary[Vector2i, bool] = visibility.compute_visible_cells(
		Vector2i(0, 0),
		3,
		blockers
	)
	var right: Dictionary[Vector2i, bool] = visibility.compute_visible_cells(
		Vector2i(2, 0),
		3,
		blockers
	)
	var explored: Dictionary[Vector2i, bool] = {}
	for cell: Vector2i in left.keys():
		explored[cell] = true
	for cell: Vector2i in right.keys():
		explored[cell] = true
	if not explored.has(Vector2i(-1, 0)) or not explored.has(Vector2i(3, 0)):
		failures.append("exploration did not accumulate across viewpoints")


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
