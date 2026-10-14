extends Node

## Contract coverage for the authored room_04_00: the world registers the room,
## the baked runtime scene contains the PuzzleBoard, and it boots a session from
## the two scene-authored blocks at 8px tiles.

const WORLD_PATH := "res://resources/worlds/the_world.tres"
const RUNTIME_SCENE_PATH := "res://scenes/rooms/generated/room_04_00/runtime.tscn"
const PUZZLE_BOARD_SCRIPT := preload("res://scripts/puzzle/view/puzzle_board.gd")


func run() -> Array[String]:
	var failures: Array[String] = []
	_assert_world_registration(failures)
	_assert_runtime_scene_boots_board(failures)
	return failures


func _assert_world_registration(failures: Array[String]) -> void:
	var world: Resource = load(WORLD_PATH)
	if world == null or not world.has_room("room_04_00"):
		failures.append("the_world does not contain room_04_00")
		return
	if world.get_room_origin_chunk("room_04_00") != Vector2i(4, 0):
		failures.append("room_04_00 is not placed at chunk (4, 0)")
	var room_data: Resource = world.get_room("room_04_00")
	if room_data == null or not room_data.spawn_ids.has("start"):
		failures.append("room_04_00 RoomData lacks the start spawn")


func _assert_runtime_scene_boots_board(failures: Array[String]) -> void:
	var scene: PackedScene = load(RUNTIME_SCENE_PATH)
	if scene == null:
		failures.append("room_04_00 runtime scene is missing")
		return
	var root: Node = scene.instantiate()
	add_child(root)
	var board: Node = root.get_node_or_null("Entities/PuzzleBoard")
	if board == null or board.get_script() != PUZZLE_BOARD_SCRIPT:
		failures.append("runtime scene is missing the PuzzleBoard")
		root.free()
		return
	if int(board.get("cell_size")) != 8:
		failures.append("PuzzleBoard cell_size is not 8 px")
	var session: Variant = board.get("session")
	if session == null or int(session.current_state.pieces.size()) != 2:
		failures.append("PuzzleBoard did not build a 2-piece session from scene pieces")
	if board.call("get_piece_at_cell", Vector2i(1, 2)) == null:
		failures.append("PieceA was not registered at cell (1, 2)")
	if board.call("get_piece_at_cell", Vector2i(5, 2)) == null:
		failures.append("PieceB was not registered at cell (5, 2)")
	if board.call("get_piece_at_cell", Vector2i(6, 2)) != null:
		failures.append("PieceB L-shape incorrectly covered cell (6, 2)")
	if board.call("get_piece_at_cell", Vector2i(5, 3)) == null:
		failures.append("PieceB L-shape did not cover cell (5, 3)")
	if board.call("get_piece_at_cell", Vector2i(6, 3)) == null:
		failures.append("PieceB L-shape did not cover cell (6, 3)")
	root.free()
