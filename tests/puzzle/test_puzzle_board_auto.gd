extends Node

## Coverage for the auto-split board: chunking a painted TileMapLayer into
## equal-size PuzzleTilePieces, including void chunks and regeneration.

const AUTO_BOARD := preload("res://scripts/puzzle/view/puzzle_board_auto.gd")
const TILESET := preload("res://resources/tilesets/primordial_tileset.tres")


func run() -> Array[String]:
    var failures: Array[String] = []
    _assert_split_creates_pieces(failures)
    _assert_generation_is_idempotent(failures)
    _assert_void_enable_flag(failures)
    _assert_out_of_range_cells_are_ignored(failures)
    _assert_missing_source_is_rejected(failures)
    return failures


func _assert_split_creates_pieces(failures: Array[String]) -> void:
    var board := _make_board(true)
    if not board.generate_pieces():
        failures.append("PuzzleBoardAuto.generate_pieces returned false for a valid picture")
        board.free()
        return
    if board.board_size != Vector2i(4, 4):
        failures.append("board_size was not derived from puzzle_size * piece_size")
    if board.get_generated_pieces().size() != 4:
        failures.append("expected 4 generated pieces, got %d" % board.get_generated_pieces().size())
    var piece_10 := board.get_node_or_null("Piece_1_0") as PuzzleTilePiece
    var piece_11 := board.get_node_or_null("Piece_1_1") as PuzzleTilePiece
    if piece_10 == null or piece_11 == null:
        failures.append("generated piece names are not Piece_<chunk_x>_<chunk_y>")
        board.free()
        return
    if piece_10.position != Vector2(16.0, 0.0) or piece_11.position != Vector2(16.0, 16.0):
        failures.append("generated pieces are not placed at their chunk origins")
    if piece_10.x_move_distance != 2 or piece_10.y_move_distance != 2:
        failures.append("generated pieces did not get piece_size as move distance")
    if not piece_10.enable:
        failures.append("normal generated pieces must be controllable")
    if piece_10.get_meta(&"authored_cell", Vector2i(-1, -1)) != Vector2i(2, 0):
        failures.append("generated pieces did not record their authored chunk cell")
    if not piece_11.is_void:
        failures.append("a chunk painted in the void layer was not generated as a void piece")
    if piece_11.enable:
        failures.append("void pieces must default to enable = false")
    if piece_11.z_index != 1:
        failures.append("void pieces must draw above normal pieces")
    var solid := piece_10.get_node_or_null("SolidTiles") as TileMapLayer
    if solid == null or not solid.collision_enabled:
        failures.append("normal pieces need a colliding SolidTiles layer")
    elif solid.tile_set != TILESET:
        failures.append("generated layers did not copy the source TileSet")
    elif solid.get_used_cells().size() != 4:
        failures.append("SolidTiles did not receive the chunk cells")
    elif solid.get_cell_atlas_coords(Vector2i(1, 1)) != Vector2i(0, 3):
        failures.append("chunk cells were not offset into piece-local coordinates")
    var void_layer := piece_11.get_node_or_null("VoidTiles") as TileMapLayer
    if void_layer == null or void_layer.collision_enabled:
        failures.append("void pieces need a non-colliding VoidTiles layer")
    elif piece_11.get_node_or_null("SolidTiles") != null:
        failures.append("void chunks must not also create SolidTiles")
    add_child(board)
    if piece_10.shape.size() != 4 or piece_11.shape.size() != 4:
        failures.append("generated tile pieces did not derive their footprints")
    if board.session == null or board.session.current_state.pieces.size() != 4:
        failures.append("PuzzleBoardAuto did not build a session from generated pieces")
    elif not board.session.definition.pieces[3].is_void:
        failures.append("the generated void piece was not registered as void")
    board.free()


func _assert_generation_is_idempotent(failures: Array[String]) -> void:
    var board := _make_board(true)
    if not board.generate_pieces() or not board.generate_pieces():
        failures.append("regeneration reported failure")
    if board.get_generated_pieces().size() != 4:
        failures.append("regeneration duplicated generated pieces")
    var piece := board.get_node_or_null("Piece_1_1") as PuzzleTilePiece
    if piece == null:
        failures.append("regeneration lost a generated piece")
    elif piece.get_node("VoidTiles").get_used_cells().size() != 4:
        failures.append("regeneration dropped generated cell data")
    board.free()


func _assert_void_enable_flag(failures: Array[String]) -> void:
    var board := _make_board(true)
    board.void_enable = true
    board.generate_pieces()
    var void_piece := board.get_node_or_null("Piece_1_1") as PuzzleTilePiece
    if void_piece == null or not void_piece.enable:
        failures.append("void_enable = true did not enable the generated void piece")
    board.free()


func _assert_out_of_range_cells_are_ignored(failures: Array[String]) -> void:
    var board := _make_board(true)
    var source := board.get_node("PictureSource") as TileMapLayer
    source.set_cell(Vector2i(4, 4), 0, Vector2i(0, 0))
    if not board.generate_pieces():
        failures.append("out-of-range cells made generation fail")
    if board.get_node_or_null("Piece_2_2") != null:
        failures.append("a cell outside the board created a chunk")
    if board.get_generated_pieces().size() != 4:
        failures.append("out-of-range cells changed the piece count")
    board.free()


func _assert_missing_source_is_rejected(failures: Array[String]) -> void:
    var board := AUTO_BOARD.new() as PuzzleBoardAuto
    board.puzzle_size = Vector2i(2, 2)
    board.piece_size = Vector2i(2, 2)
    if board.generate_pieces():
        failures.append("generate_pieces succeeded without a source layer")
    if not board.get_generated_pieces().is_empty():
        failures.append("generate_pieces modified the board on failure")
    board.free()


func _make_board(with_void: bool) -> PuzzleBoardAuto:
    var board := AUTO_BOARD.new() as PuzzleBoardAuto
    board.puzzle_size = Vector2i(2, 2)
    board.piece_size = Vector2i(2, 2)
    board.cell_size = 8
    var source := _layer("PictureSource", [
        {"cell": Vector2i(0, 0), "atlas": Vector2i(0, 0)}, {"cell": Vector2i(1, 0), "atlas": Vector2i(0, 0)},
        {"cell": Vector2i(0, 1), "atlas": Vector2i(0, 0)}, {"cell": Vector2i(1, 1), "atlas": Vector2i(0, 0)},
        {"cell": Vector2i(2, 0), "atlas": Vector2i(0, 3)}, {"cell": Vector2i(3, 0), "atlas": Vector2i(0, 3)},
        {"cell": Vector2i(2, 1), "atlas": Vector2i(0, 3)}, {"cell": Vector2i(3, 1), "atlas": Vector2i(0, 3)},
        {"cell": Vector2i(0, 2), "atlas": Vector2i(0, 0)}, {"cell": Vector2i(1, 2), "atlas": Vector2i(0, 0)},
        {"cell": Vector2i(0, 3), "atlas": Vector2i(0, 0)}, {"cell": Vector2i(1, 3), "atlas": Vector2i(0, 0)},
    ])
    board.add_child(source)
    board.source_layer_path = ^"PictureSource"
    if with_void:
        var void_source := _layer("VoidSource", [
            {"cell": Vector2i(2, 2), "atlas": Vector2i(0, 5)}, {"cell": Vector2i(3, 2), "atlas": Vector2i(0, 5)},
            {"cell": Vector2i(2, 3), "atlas": Vector2i(0, 5)}, {"cell": Vector2i(3, 3), "atlas": Vector2i(0, 5)},
        ])
        board.add_child(void_source)
        board.void_layer_path = ^"VoidSource"
    return board


func _layer(layer_name: String, cells: Array) -> TileMapLayer:
    var layer := TileMapLayer.new()
    layer.name = layer_name
    layer.tile_set = TILESET
    layer.collision_enabled = false
    for entry: Dictionary in cells:
        layer.set_cell(entry["cell"], 0, entry["atlas"], 0)
    return layer
