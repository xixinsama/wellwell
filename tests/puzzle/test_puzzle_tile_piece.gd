extends Node

## Coverage for tile-authored sliding regions: footprint derivation, background
## exclusion, board integration and the legacy polygon fallback.

const TILESET := preload("res://resources/tilesets/primordial_tileset.tres")
const TILE_PIECE_SCRIPT := preload("res://scripts/puzzle/view/puzzle_tile_piece.gd")


func run() -> Array[String]:
	var failures: Array[String] = []
	_assert_footprint_uses_colliding_tiles(failures)
	_assert_board_scans_tile_piece(failures)
	_assert_void_layer_builds_player_body(failures)
	_assert_void_layer_wins_hybrid(failures)
	_assert_void_selection_priority(failures)
	_assert_polygon_fallback(failures)
	return failures


func _assert_footprint_uses_colliding_tiles(failures: Array[String]) -> void:
	var piece := _make_tile_piece()
	piece.position = Vector2(16.0, 8.0)
	add_child(piece)

	var solid := piece.get_node("SolidTiles") as TileMapLayer
	var one_way := piece.get_node("OneWayTiles") as TileMapLayer
	var back := piece.get_node("BackTiles") as TileMapLayer
	# Wall + one-way platform: both have tileset physics and must count.
	solid.set_cell(Vector2i.ZERO, 0, Vector2i(0, 0))
	one_way.set_cell(Vector2i(1, 0), 0, Vector2i(1, 4))
	# Background tile painted on the solid layer has no physics: no footprint.
	solid.set_cell(Vector2i(2, 0), 0, Vector2i(0, 5))
	# Background layer alone never enlarges the footprint.
	back.set_cell(Vector2i(3, 0), 0, Vector2i(0, 5))
	piece.call("_refresh_from_polygon")

	if piece.get_logical_cell() != Vector2i(2, 1):
		failures.append("tile piece did not derive its anchor cell from its position")
	var expected: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0)]
	if piece.shape != expected:
		failures.append("tile piece footprint was not limited to colliding tiles: %s" % [piece.shape])
	if piece.get_bounds() != Rect2i(0, 0, 2, 1):
		failures.append("tile piece bounds followed non-colliding background cells")
	if piece.wall_shape != [Vector2i.ZERO]:
		failures.append("tile piece wall classification was wrong: %s" % [piece.wall_shape])
	if piece.one_way_shape != [Vector2i(1, 0)]:
		failures.append("tile piece one-way classification was wrong: %s" % [piece.one_way_shape])

	solid.set_cell(Vector2i(0, 1), 0, Vector2i(0, 0))
	piece.call("_refresh_from_polygon")
	if not piece.shape.has(Vector2i(0, 1)):
		failures.append("tile piece footprint did not refresh after painting a wall")
	if not piece.wall_shape.has(Vector2i(0, 1)):
		failures.append("tile piece did not classify the new wall cell")
	if piece.one_way_shape.has(Vector2i(0, 1)):
		failures.append("tile piece classified a wall cell as one-way")
	if piece.shape.has(Vector2i(2, 0)) or piece.shape.has(Vector2i(3, 0)):
		failures.append("tile piece footprint included physics-less background tiles")

	piece.queue_free()


func _assert_board_scans_tile_piece(failures: Array[String]) -> void:
	var board := PuzzleBoard.new()
	board.board_size = Vector2i(8, 4)
	board.cell_size = 8

	var piece := _make_tile_piece()
	piece.position = Vector2(16.0, 8.0)
	piece.x_move_distance = 3
	piece.y_move_distance = 2
	var solid := piece.get_node("SolidTiles") as TileMapLayer
	var one_way := piece.get_node("OneWayTiles") as TileMapLayer
	solid.set_cell(Vector2i.ZERO, 0, Vector2i(0, 0))
	one_way.set_cell(Vector2i(1, 0), 0, Vector2i(1, 4))

	board.add_child(piece)
	add_child(board)

	var session: Variant = board.get("session")
	if session == null or session.current_state.pieces.size() != 1:
		failures.append("PuzzleBoard did not build a session from a tile piece")
	else:
		var state_piece: Variant = session.current_state.pieces[0]
		if state_piece.cell != Vector2i(2, 1):
			failures.append("PuzzleBoard registered the tile piece at the wrong anchor")
		var definition_piece: Variant = session.definition.pieces[0]
		if not definition_piece.shape.has(Vector2i.ZERO):
			failures.append("PuzzleBoard did not copy the tile piece footprint into the session")
		if not definition_piece.shape.has(Vector2i(1, 0)):
			failures.append("PuzzleBoard dropped the one-way platform cell from the footprint")
		if not definition_piece.wall_shape.has(Vector2i.ZERO):
			failures.append("PuzzleBoard did not copy the wall classification")
		if not definition_piece.one_way_shape.has(Vector2i(1, 0)):
			failures.append("PuzzleBoard did not copy the one-way classification")

	board.queue_free()


func _assert_void_layer_builds_player_body(failures: Array[String]) -> void:
	var piece := _make_void_piece()
	add_child(piece)
	var void_layer := piece.get_node("VoidTiles") as TileMapLayer
	void_layer.set_cell(Vector2i.ZERO, 0, Vector2i(0, 0))
	void_layer.set_cell(Vector2i(1, 0), 0, Vector2i(0, 0))
	piece.call("_refresh_from_polygon")
	if not piece.is_void:
		failures.append("VoidTiles did not mark the piece as void")
	if piece.shape.size() != 2:
		failures.append("void footprint did not use the painted VoidTiles cells")
	if not piece.wall_shape.is_empty() or not piece.one_way_shape.is_empty():
		failures.append("void piece leaked wall or one-way cells")
	var body := piece.get_node_or_null("VoidBody") as StaticBody2D
	if body == null:
		failures.append("void piece did not build a player-only body")
	elif body.collision_layer != 8 or body.collision_mask != 0:
		failures.append("void body used the wrong collision layer or mask")
	elif body.get_child_count() != 2:
		failures.append("void body did not create one shape per void cell")
	piece.queue_free()


func _assert_void_layer_wins_hybrid(failures: Array[String]) -> void:
	var piece := _make_void_piece()
	var void_layer := piece.get_node("VoidTiles") as TileMapLayer
	var solid := piece.get_node("SolidTiles") as TileMapLayer
	void_layer.set_cell(Vector2i.ZERO, 0, Vector2i(0, 0))
	solid.set_cell(Vector2i(1, 0), 0, Vector2i(0, 0))
	add_child(piece)
	piece.call("_refresh_from_polygon")
	if not piece.is_void or piece.shape != [Vector2i.ZERO]:
		failures.append("VoidTiles did not win over SolidTiles in a hybrid piece")
	if solid.collision_enabled:
		failures.append("hybrid void piece left SolidTiles collision enabled")
	piece.queue_free()


func _assert_void_selection_priority(failures: Array[String]) -> void:
	var board := PuzzleBoard.new()
	board.board_size = Vector2i(4, 3)
	board.cell_size = 8
	var normal := _make_tile_piece()
	normal.position = Vector2(0.0, 0.0)
	var normal_solid := normal.get_node("SolidTiles") as TileMapLayer
	normal_solid.set_cell(Vector2i.ZERO, 0, Vector2i(0, 0))
	normal_solid.set_cell(Vector2i(2, 0), 0, Vector2i(0, 0))
	var void_piece := _make_void_piece()
	void_piece.position = Vector2(0.0, 0.0)
	var void_layer := void_piece.get_node("VoidTiles") as TileMapLayer
	void_layer.set_cell(Vector2i.ZERO, 0, Vector2i(0, 0))
	board.add_child(normal)
	board.add_child(void_piece)
	add_child(board)
	var picked: PuzzlePiece = board.call("get_piece_at_cell", Vector2i.ZERO)
	if picked != void_piece:
		failures.append("void piece did not win hit-testing against a normal piece")
	var normal_pick: PuzzlePiece = board.call("get_piece_at_cell", Vector2i(2, 0))
	if normal_pick != normal:
		failures.append("a void piece outside its footprint stole a normal piece click")
	board.queue_free()


func _assert_polygon_fallback(failures: Array[String]) -> void:
	var piece := TILE_PIECE_SCRIPT.new() as PuzzleTilePiece
	piece.cell_size = 8
	piece.polygon = PackedVector2Array([
		Vector2.ZERO,
		Vector2(16.0, 0.0),
		Vector2(16.0, 8.0),
		Vector2(0.0, 8.0),
	])
	add_child(piece)
	if piece.shape.size() != 2:
		failures.append("PuzzleTilePiece did not fall back to its Polygon2D face")
	if piece.wall_shape.size() != 2 or not piece.one_way_shape.is_empty():
		failures.append("legacy polygon fallback was not classified as all walls")
	piece.queue_free()


func _make_tile_piece() -> PuzzleTilePiece:
	var piece := TILE_PIECE_SCRIPT.new() as PuzzleTilePiece
	piece.cell_size = 8
	piece.add_child(_make_layer("BackTiles", false))
	piece.add_child(_make_layer("SolidTiles", true))
	piece.add_child(_make_layer("OneWayTiles", true))
	piece.add_child(_make_layer("DetailTiles", false))
	return piece


func _make_void_piece() -> PuzzleTilePiece:
	var piece := TILE_PIECE_SCRIPT.new() as PuzzleTilePiece
	piece.cell_size = 8
	piece.add_child(_make_layer("BackTiles", false))
	piece.add_child(_make_layer("SolidTiles", true))
	piece.add_child(_make_layer("OneWayTiles", true))
	piece.add_child(_make_layer("DetailTiles", false))
	piece.add_child(_make_layer("VoidTiles", false))
	return piece


func _make_layer(layer_name: String, collision_enabled: bool) -> TileMapLayer:
	var layer := TileMapLayer.new()
	layer.name = layer_name
	layer.tile_set = TILESET
	layer.collision_enabled = collision_enabled
	return layer
