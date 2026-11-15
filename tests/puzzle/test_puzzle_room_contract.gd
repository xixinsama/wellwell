extends Node

## Contract coverage for the authored room_04_00: the world registers the room,
## the baked runtime scene contains the PuzzleBoard, and it boots a session from
## three tile-authored sliding regions at 8px tiles.

const WORLD_PATH := "res://resources/worlds/the_world.tres"
const RUNTIME_SCENE_PATH := "res://scenes/rooms/generated/room_04_00/runtime.tscn"
const PUZZLE_BOARD_SCRIPT := preload("res://scripts/puzzle/view/puzzle_board.gd")
const PUZZLE_MOVE := preload("res://scripts/puzzle/core/puzzle_move.gd")


func run() -> Array[String]:
	var failures: Array[String] = []
	_assert_world_registration(failures)
	_assert_runtime_scene_boots_board(failures)
	_assert_player_riding_rules(failures)
	_assert_one_way_overlap_rules(failures)
	_assert_mode_overlay(failures)
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
	if session == null or int(session.current_state.pieces.size()) != 4:
		failures.append("PuzzleBoard did not build a 4-piece session from scene pieces")
	else:
		_assert_tile_pieces(board.get("_pieces"), failures)
		if int(session.definition.pieces[0].x_move_distance) != 4 or int(session.definition.pieces[0].y_move_distance) != 4:
			failures.append("PieceA axis move distances were not preserved through the bake")
		if int(session.definition.pieces[2].x_move_distance) != 2 or int(session.definition.pieces[2].y_move_distance) != 2:
			failures.append("PieceC axis move distances were not preserved through the bake")
	if board.call("get_piece_at_cell", Vector2i(16, 5)) == null:
		failures.append("PieceA was not registered at cell (16, 5)")
	if board.call("get_piece_at_cell", Vector2i(7, 16)) == null:
		failures.append("PieceB was not registered at cell (7, 16)")
	if board.call("get_piece_at_cell", Vector2i(3, 10)) == null:
		failures.append("PieceC was not registered at cell (3, 10)")
	if board.call("get_piece_at_cell", Vector2i(0, 8)) == null:
		failures.append("the legacy scene piece was not registered at cell (0, 8)")
	if board.call("get_piece_at_cell", Vector2i(11, 17)) == null:
		failures.append("PieceB L-shape did not cover cell (11, 17)")
	if board.call("get_piece_at_cell", Vector2i(11, 18)) != null:
		failures.append("PieceB L-shape incorrectly covered hole cell (11, 18)")
	if board.call("get_piece_at_cell", Vector2i(7, 10)) == null:
		failures.append("PieceC L-shape did not cover cell (7, 10)")
	if board.call("get_piece_at_cell", Vector2i(7, 11)) != null:
		failures.append("PieceC L-shape incorrectly covered hole cell (7, 11)")
	if board.call("get_piece_at_cell", Vector2i(24, 11)) != null:
		failures.append("PieceA background-only hole incorrectly blocked cell (24, 11)")
	root.free()


func _assert_tile_pieces(pieces: Array, failures: Array[String]) -> void:
	var expected_cells: Array[Vector2i] = [Vector2i(16, 5), Vector2i(7, 16), Vector2i(3, 10)]
	for i in 3:
		var piece := pieces[i] as PuzzleTilePiece
		if piece == null:
			failures.append("scene piece %d is not a PuzzleTilePiece" % i)
			continue
		if Vector2i(piece.get("logical_cell")) != expected_cells[i]:
			failures.append("scene piece %d has unexpected anchor cell" % i)
		var back := piece.get_node_or_null("BackTiles") as TileMapLayer
		var solid := piece.get_node_or_null("SolidTiles") as TileMapLayer
		var one_way := piece.get_node_or_null("OneWayTiles") as TileMapLayer
		if back == null or back.collision_enabled:
			failures.append("scene piece %d lacks a non-colliding BackTiles layer" % i)
		if solid == null or not solid.collision_enabled:
			failures.append("scene piece %d lacks a colliding SolidTiles layer" % i)
		if one_way == null or not one_way.collision_enabled:
			failures.append("scene piece %d lacks a colliding OneWayTiles layer" % i)
		if back != null and solid != null and one_way != null:
			var footprint := solid.get_used_cells().size() + one_way.get_used_cells().size()
			if back.get_used_cells().size() <= footprint:
				failures.append("scene piece %d background did not extend beyond the footprint" % i)
			if piece.shape.size() != footprint:
				failures.append("scene piece %d footprint did not match its colliding tile cells" % i)
			if piece.wall_shape.size() != solid.get_used_cells().size():
				failures.append("scene piece %d wall classification did not match SolidTiles" % i)
			if piece.one_way_shape.size() != one_way.get_used_cells().size():
				failures.append("scene piece %d one-way classification did not match OneWayTiles" % i)
	var piece_a := pieces[0] as PuzzleTilePiece
	if piece_a == null:
		return
	if piece_a.get_node("OneWayTiles").get_cell_atlas_coords(Vector2i(0, 0)) != Vector2i(0, 4):
		failures.append("PieceA top-left cell is not a one-way platform tile")
	if piece_a.get_node("OneWayTiles").z_index <= piece_a.get_node("SolidTiles").z_index:
		failures.append("PieceA one-way layer is not drawn above the wall layer")
	var legacy := pieces[3] as PuzzlePiece
	if legacy == null or legacy is PuzzleTilePiece:
		failures.append("the fourth scene piece is not the expected legacy polygon piece")
	elif legacy.wall_shape.size() != legacy.shape.size() or not legacy.one_way_shape.is_empty():
		failures.append("the legacy scene piece was not classified as all walls")
	return


func _assert_player_riding_rules(failures: Array[String]) -> void:
	var scene: PackedScene = load(RUNTIME_SCENE_PATH)
	if scene == null:
		failures.append("room_04_00 runtime scene is missing")
		return
	var root: Node = scene.instantiate()
	add_child(root)
	var board: Node = root.get_node_or_null("Entities/PuzzleBoard")
	if board == null:
		failures.append("riding test could not find the PuzzleBoard")
		root.free()
		return
	var player := Node2D.new()
	player.name = "TestPlayer"
	player.add_to_group("player")
	root.add_child(player)
	board.call("_resolve_player_lazy")

	var pieces: Array = board.get("_pieces")
	if pieces.size() < 2:
		failures.append("riding test needs the two scene pieces")
		root.free()
		return
	var piece_a: Node = pieces[0]
	var piece_b: Node = pieces[1]

	# Case 1: standing on the one-way top of PieceA, outside its bounding rect.
	board.call("set_player_to_cell", Vector2i(16, 4))
	if not board.call("_player_rides", piece_a):
		failures.append("player standing on PieceA did not ride")
	# Case 2: inside PieceB's bounding rect with empty support.
	board.call("set_player_to_cell", Vector2i(10, 18))
	if not board.call("_player_rides", piece_b):
		failures.append("player inside PieceB's rect did not ride")
	# Far from every piece: no ride.
	board.call("set_player_to_cell", Vector2i(0, 0))
	if board.call("_player_rides", piece_a):
		failures.append("distant player incorrectly rode PieceA")
	# Touching from below (piece above the head): no ride.
	board.call("set_player_to_cell", Vector2i(16, 15))
	if board.call("_player_rides", piece_a):
		failures.append("player under PieceA incorrectly rode")
	root.free()


func _assert_one_way_overlap_rules(failures: Array[String]) -> void:
	var scene: PackedScene = load(RUNTIME_SCENE_PATH)
	if scene == null:
		failures.append("room_04_00 runtime scene is missing")
		return
	var root: Node = scene.instantiate()
	add_child(root)
	var board: Node = root.get_node_or_null("Entities/PuzzleBoard")
	if board == null:
		failures.append("overlap test could not find the PuzzleBoard")
		root.free()
		return
	var pieces: Array = board.get("_pieces")
	var session: Variant = board.get("session")
	if pieces.size() < 4 or session == null:
		failures.append("overlap test needs the four scene pieces")
		root.free()
		return
	# The fourth (legacy wall) piece starts at (0, 8), 3x3. PieceC's top row
	# has one-way cells starting at (3, 10). Moving right enters that one-way
	# cell from the side and is allowed to overlap.
	if not session.try_move(PUZZLE_MOVE.new(3, Vector2i(0, 8), Vector2i(1, 8))):
		failures.append("wall could not enter PieceC's one-way cell from the left")
	if board.call("get_piece_at_cell", Vector2i(3, 10)) != pieces[2]:
		failures.append("one-way platform was not selected above the overlapping wall")
	# Moving down from the overlap would enter PieceC's one-way cell from above.
	if session.try_move(PUZZLE_MOVE.new(3, Vector2i(1, 8), Vector2i(1, 9))):
		failures.append("wall slid down into a one-way cell")
	root.free()


func _assert_mode_overlay(failures: Array[String]) -> void:
	var scene: PackedScene = load(RUNTIME_SCENE_PATH)
	if scene == null:
		failures.append("room_04_00 runtime scene is missing")
		return
	var root: Node = scene.instantiate()
	add_child(root)
	var board: Node = root.get_node_or_null("Entities/PuzzleBoard")
	if board == null:
		failures.append("mode overlay test could not find the PuzzleBoard")
		root.free()
		return
	if board.get_node_or_null("ModeHud") != null:
		failures.append("PuzzleBoard still creates the mode text HUD")
	var overlay: Node2D = board.get_node_or_null("ModeOverlay") as Node2D
	if overlay == null:
		failures.append("PuzzleBoard did not create its mode overlay")
		root.free()
		return
	if overlay.visible:
		failures.append("mode overlay was visible outside slider mode")
	board.call("_enter_drag_mode")
	if not overlay.visible:
		failures.append("mode overlay did not appear in slider mode")
	var piece: PuzzlePiece = board.get("_pieces")[0]
	board.call("_select_piece", piece)
	if overlay.get("_selected") != piece:
		failures.append("mode overlay did not mark the selected piece solid")
	board.call("_exit_drag_mode")
	if overlay.visible:
		failures.append("mode overlay stayed visible after leaving slider mode")
	root.free()
