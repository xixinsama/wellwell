extends Node

## Coverage for the scramble pipeline: the pure random walk, the PuzzleBoard
## adoption API and the PuzzleBoardShuffler node component.

const PuzzleScrambler := preload("res://scripts/puzzle/systems/puzzle_scrambler.gd")
const SlidingPuzzleRuleSet := preload("res://scripts/puzzle/rules/sliding_puzzle_rule_set.gd")
const PuzzleSession := preload("res://scripts/puzzle/systems/puzzle_session.gd")
const PUZZLE_BOARD := preload("res://scripts/puzzle/view/puzzle_board.gd")
const PUZZLE_SHUFFLER := preload("res://scripts/puzzle/view/puzzle_board_shuffler.gd")
const TILESET := preload("res://resources/tilesets/primordial_tileset.tres")


func run() -> Array[String]:
    var failures: Array[String] = []
    _assert_scrambler_walks_around_void(failures)
    _assert_scrambler_is_deterministic(failures)
    _assert_scrambler_void_only_filter(failures)
    _assert_scrambler_rejects_packed_board(failures)
    _assert_scrambler_handles_two_voids(failures)
    _assert_board_scramble_updates_initial_layout(failures)
    _assert_apply_initial_layout_adopts_state(failures)
    _assert_shuffler_node_scrambles_on_ready(failures)
    _assert_child_shuffler_can_scramble_now(failures)
    return failures


# --- Pure scrambler -----------------------------------------------------------

func _assert_scrambler_walks_around_void(failures: Array[String]) -> void:
    var def := _void_board()
    var rules := SlidingPuzzleRuleSet.new(def)
    var start := PuzzleSession.new(def).current_state
    var rng := RandomNumberGenerator.new()
    rng.seed = 1
    var result: BoardState = PuzzleScrambler.build_scrambled_state(def, rules, start, 40, rng, true, true)
    if result == null:
        failures.append("scrambler returned null for a board with a void slider")
        return
    if result.get_hash_key() == start.get_hash_key():
        failures.append("scrambler returned the start layout")
    _assert_state_legal(def, result, failures, "void walk")


func _assert_scrambler_is_deterministic(failures: Array[String]) -> void:
    var def := _void_board()
    var rules := SlidingPuzzleRuleSet.new(def)
    var start := PuzzleSession.new(def).current_state
    var first: BoardState = _scramble_with_seed(def, rules, start, 4242)
    var second: BoardState = _scramble_with_seed(def, rules, start, 4242)
    if first == null or second == null:
        failures.append("deterministic scramble returned null")
        return
    if first.get_hash_key() != second.get_hash_key():
        failures.append("same seed produced different scrambled layouts")
    var other: BoardState = _scramble_with_seed(def, rules, start, 99)
    if other != null and other.get_hash_key() == first.get_hash_key():
        failures.append("different seeds produced the same scrambled layout")


func _assert_scrambler_void_only_filter(failures: Array[String]) -> void:
    var def := _definition(Vector2i(4, 4), [
        _piece(&"a", Vector2i(0, 0), Vector2i(2, 2), false),
        _piece(&"b", Vector2i(2, 0), Vector2i(2, 2), false),
        _piece(&"c", Vector2i(0, 2), Vector2i(2, 2), false),
    ])
    var rules := SlidingPuzzleRuleSet.new(def)
    var start := PuzzleSession.new(def).current_state
    var rng := RandomNumberGenerator.new()
    rng.seed = 5
    if PuzzleScrambler.build_scrambled_state(def, rules, start, 20, rng, true, true) != null:
        failures.append("void_only scramble succeeded on a board without void sliders")
    rng.seed = 5
    var result: BoardState = PuzzleScrambler.build_scrambled_state(def, rules, start, 20, rng, false, true)
    if result == null or result.get_hash_key() == start.get_hash_key():
        failures.append("non-void_only scramble did not move a board with an empty slot")
    else:
        _assert_state_legal(def, result, failures, "empty slot")


func _assert_scrambler_rejects_packed_board(failures: Array[String]) -> void:
    var def := _definition(Vector2i(4, 4), [
        _piece(&"a", Vector2i(0, 0), Vector2i(2, 2), false),
        _piece(&"b", Vector2i(2, 0), Vector2i(2, 2), false),
        _piece(&"c", Vector2i(0, 2), Vector2i(2, 2), false),
        _piece(&"d", Vector2i(2, 2), Vector2i(2, 2), false),
    ])
    var rules := SlidingPuzzleRuleSet.new(def)
    var start := PuzzleSession.new(def).current_state
    var rng := RandomNumberGenerator.new()
    rng.seed = 3
    if PuzzleScrambler.build_scrambled_state(def, rules, start, 20, rng, false, true) != null:
        failures.append("scrambler moved a packed board with no empty slot")


func _assert_scrambler_handles_two_voids(failures: Array[String]) -> void:
    var pieces: Array = []
    for y in 3:
        for x in 3:
            pieces.append(_piece(
                StringName("p_%d_%d" % [x, y]),
                Vector2i(x * 2, y * 2),
                Vector2i(2, 2),
                (x == 0 and y == 0) or (x == 2 and y == 2)
            ))
    var def := _definition(Vector2i(6, 6), pieces)
    var rules := SlidingPuzzleRuleSet.new(def)
    var start := PuzzleSession.new(def).current_state
    var rng := RandomNumberGenerator.new()
    rng.seed = 17
    var result: BoardState = PuzzleScrambler.build_scrambled_state(def, rules, start, 60, rng, true, true)
    if result == null or result.get_hash_key() == start.get_hash_key():
        failures.append("scrambler did not move a board with two void sliders")
    else:
        _assert_state_legal(def, result, failures, "two voids")


# --- PuzzleBoard adoption API -------------------------------------------------

func _assert_board_scramble_updates_initial_layout(failures: Array[String]) -> void:
    var board := _make_board_with_void()
    var start := board.session.current_state.get_hash_key()
    if not board.scramble(40, 7, true, true):
        failures.append("PuzzleBoard.scramble returned false on a board with a void slider")
        return
    if board.session.current_state.get_hash_key() == start:
        failures.append("PuzzleBoard.scramble did not change the layout")
    var state: BoardState = board.session.current_state
    for i in state.pieces.size():
        if board.definition.pieces[i].initial_cell != state.pieces[i].cell:
            failures.append("scramble did not adopt piece %d as new initial cell" % i)
    if board.session.get_move_count() != 0:
        failures.append("scramble left a non-zero move count")
    if board.session.undo():
        failures.append("scramble left an undo entry")
    if board.session.reset():
        failures.append("reset after scramble was not a no-op")
    var pieces: Array[PuzzlePiece] = []
    for child in board.get_children():
        if child is PuzzlePiece:
            pieces.append(child as PuzzlePiece)
    if pieces.size() != state.pieces.size():
        failures.append("scrambled board lost pieces")
    for i in pieces.size():
        if pieces[i].get_logical_cell() != state.pieces[i].cell:
            failures.append("piece %d node cell was not synced after scramble" % i)
        if not pieces[i].position.is_equal_approx(pieces[i].cell_to_world(state.pieces[i].cell)):
            failures.append("piece %d node position was not synced after scramble" % i)
    _assert_state_legal(board.definition, state, failures, "board scramble")
    board.free()


func _assert_apply_initial_layout_adopts_state(failures: Array[String]) -> void:
    var board := _make_board_with_void()
    var state: BoardState = board.session.current_state.duplicate_state()
    # Move piece 0 into the void chunk's cells (no legality check here: adoption
    # is a data operation; the scrambler is the thing that only feeds it legal
    # turns).
    state.pieces[0].cell = Vector2i(2, 2)
    board.apply_initial_layout(state)
    if board.definition.pieces[0].initial_cell != Vector2i(2, 2):
        failures.append("apply_initial_layout did not write the new initial cell")
    if board.session.current_state.pieces[0].cell != Vector2i(2, 2):
        failures.append("apply_initial_layout did not restart the session from the new layout")
    var piece := board.get_children().filter(func(child): return child is PuzzlePiece)[0] as PuzzlePiece
    if piece.get_logical_cell() != Vector2i(2, 2):
        failures.append("apply_initial_layout did not sync the piece's logical cell")
    if not piece.position.is_equal_approx(piece.cell_to_world(Vector2i(2, 2))):
        failures.append("apply_initial_layout did not sync the piece's node position")
    if board.session.undo() or board.session.reset() or board.session.get_move_count() != 0:
        failures.append("apply_initial_layout left history behind")
    board.free()


# --- Shuffler node ------------------------------------------------------------

func _assert_shuffler_node_scrambles_on_ready(failures: Array[String]) -> void:
    var root := Node2D.new()
    add_child(root)
    var board := _make_board_with_void(root)
    var start := board.session.current_state.get_hash_key()
    var shuffler := PUZZLE_SHUFFLER.new() as PuzzleBoardShuffler
    shuffler.board_path = ^"../PuzzleBoard"
    shuffler.steps = 40
    shuffler.seed = 11
    root.add_child(shuffler)
    if board.session.current_state.get_hash_key() == start:
        failures.append("PuzzleBoardShuffler did not scramble a sibling board on ready")
    if not shuffler.shuffle_now():
        failures.append("PuzzleBoardShuffler.shuffle_now returned false")
    root.free()


func _assert_child_shuffler_can_scramble_now(failures: Array[String]) -> void:
    var board := _make_board_with_void()
    var shuffler := PUZZLE_SHUFFLER.new() as PuzzleBoardShuffler
    shuffler.shuffle_on_ready = false
    shuffler.steps = 40
    shuffler.seed = 21
    board.add_child(shuffler)
    var start := board.session.current_state.get_hash_key()
    if not shuffler.shuffle_now():
        failures.append("child PuzzleBoardShuffler.shuffle_now returned false")
    if board.session.current_state.get_hash_key() == start:
        failures.append("child PuzzleBoardShuffler.shuffle_now did not scramble")
    board.free()


# --- Helpers ------------------------------------------------------------------

func _make_board_with_void(parent: Node = null) -> PuzzleBoard:
    var board := PUZZLE_BOARD.new() as PuzzleBoard
    board.name = "PuzzleBoard"
    board.board_size = Vector2i(4, 4)
    board.cell_size = 8
    board.add_child(_make_tile_piece(Vector2i(0, 0), false))
    board.add_child(_make_tile_piece(Vector2i(2, 0), false))
    board.add_child(_make_tile_piece(Vector2i(0, 2), false))
    board.add_child(_make_tile_piece(Vector2i(2, 2), true))
    if parent != null:
        parent.add_child(board)
    else:
        add_child(board)
    return board


func _make_tile_piece(cell: Vector2i, is_void: bool) -> PuzzleTilePiece:
    var piece := PuzzleTilePiece.new()
    piece.position = Vector2(cell * 8)
    piece.x_move_distance = 2
    piece.y_move_distance = 2
    var layer := TileMapLayer.new()
    layer.name = "VoidTiles" if is_void else "SolidTiles"
    layer.tile_set = TILESET
    layer.collision_enabled = not is_void
    for y in 2:
        for x in 2:
            layer.set_cell(Vector2i(x, y), 0, Vector2i(0, 5) if is_void else Vector2i(0, 0))
    piece.add_child(layer)
    return piece


func _void_board() -> PuzzleDefinition:
    var pieces: Array = []
    for y in 3:
        for x in 3:
            pieces.append(_piece(
                StringName("p_%d_%d" % [x, y]),
                Vector2i(x * 2, y * 2),
                Vector2i(2, 2),
                x == 2 and y == 2
            ))
    return _definition(Vector2i(6, 6), pieces)


func _definition(board_size: Vector2i, pieces: Array) -> PuzzleDefinition:
    var def := PuzzleDefinition.new()
    def.board = BoardDefinition.new()
    def.board.board_size = board_size
    var index := 0
    for piece: PieceDefinition in pieces:
        piece.id = StringName("piece_%d" % index)
        def.pieces.append(piece)
        index += 1
    return def


func _piece(id: StringName, cell: Vector2i, size: Vector2i, is_void: bool) -> PieceDefinition:
    var piece := PieceDefinition.new()
    piece.id = id
    piece.shape = PieceDefinition.make_rect_shape(size)
    piece.initial_cell = cell
    piece.is_void = is_void
    piece.enable = not is_void
    piece.x_move_distance = size.x
    piece.y_move_distance = size.y
    return piece


func _scramble_with_seed(def: PuzzleDefinition, rules: PuzzleRuleSet, start: BoardState, seed_value: int) -> BoardState:
    var rng := RandomNumberGenerator.new()
    rng.seed = seed_value
    return PuzzleScrambler.build_scrambled_state(def, rules, start, 40, rng, true, true)


func _assert_state_legal(
    def: PuzzleDefinition,
    state: BoardState,
    failures: Array[String],
    label: String
) -> void:
    var occupied: Dictionary = {}
    for i in state.pieces.size():
        var piece_def: PieceDefinition = def.pieces[i]
        var cell: Vector2i = state.pieces[i].cell
        for offset: Vector2i in piece_def.shape:
            var world := cell + offset
            if not def.board.contains_cell(world):
                failures.append("%s: piece %d left the board at %s" % [label, i, world])
            if not piece_def.is_void:
                if occupied.has(world):
                    failures.append("%s: normal pieces overlap at %s" % [label, world])
                occupied[world] = true
