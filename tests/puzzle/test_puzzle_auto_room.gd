extends Node

## Contract coverage for the migrated main_room_02_00: the baked runtime scene
## carries the generated 3x3 picture (8 solid sliders + one 25-cell void
## diamond), the shuffler scrambled it on load, and the editor-only source
## layers stayed out of the runtime.

const AUTO_BOARD := preload("res://scripts/puzzle/view/puzzle_board_auto.gd")
const RUNTIME := "res://scenes/rooms/generated/main_room_02_00/runtime.tscn"
const BOARD_SIZE := Vector2i(21, 21)
const VOID_CELLS := 25
const AUTHORED_CELL_META := &"authored_cell"


func run() -> Array[String]:
    var failures: Array[String] = []
    var scene: PackedScene = load(RUNTIME)
    if scene == null:
        failures.append("main_room_02_00 runtime scene is missing")
        return failures
    var root: Node = scene.instantiate()
    add_child(root)
    if root.get_node_or_null("PreviewOnly") != null:
        failures.append("PreviewOnly leaked into the baked runtime scene")
    var board := root.get_node_or_null("Entities/PuzzleBoard")
    if board == null or board.get_script() != AUTO_BOARD:
        failures.append("main_room_02_00 PuzzleBoard is not a PuzzleBoardAuto")
        root.free()
        return failures
    if board.board_size != BOARD_SIZE:
        failures.append("main_room_02_00 board is not 21x21 cells")
    if board.get_node_or_null("PuzzleSourceTiles") != null or board.get_node_or_null("PuzzleVoidTiles") != null:
        failures.append("the runtime board still carries editor-only source layers")
    var pieces: Array = board.call("get_generated_pieces")
    if pieces.size() != 9:
        failures.append("main_room_02_00 should generate 9 sliders, got %d" % pieces.size())
    var void_count := 0
    var moved := 0
    for piece: PuzzleTilePiece in pieces:
        var authored := Vector2i(piece.get_meta(AUTHORED_CELL_META, Vector2i.ZERO))
        if piece.get_logical_cell() != authored:
            moved += 1
        if piece.is_void:
            void_count += 1
            if piece.shape.size() != VOID_CELLS:
                failures.append("main_room_02_00 void slider is not the 25-cell diamond")
            if piece.get_bounds() != Rect2i(0, 0, 7, 7):
                failures.append("main_room_02_00 void slider bounds are not 7x7")
            if authored != Vector2i(7, 7):
                failures.append("main_room_02_00 void slider was authored at the wrong chunk")
        elif piece.shape.size() != 49:
            failures.append("main_room_02_00 solid slider does not cover its full 7x7 chunk")
    if void_count != 1:
        failures.append("main_room_02_00 should have exactly one void slider")
    if moved == 0:
        failures.append("the shuffler did not scramble main_room_02_00 on load")
    var shuffler := root.get_node_or_null("Entities/PuzzleBoardShuffler")
    if shuffler == null:
        failures.append("main_room_02_00 is missing the PuzzleBoardShuffler")
    elif not bool(shuffler.get("void_only")):
        failures.append("main_room_02_00 shuffler should only walk void turns")
    if board.session == null or board.session.current_state.pieces.size() != 9:
        failures.append("main_room_02_00 did not boot a 9-piece session")
    root.free()
    return failures
