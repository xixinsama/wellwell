class_name PuzzleBoardShuffler
extends Node

## Scrambles a PuzzleBoard on load by walking random legal turns.
##
## The walk always ends on a layout different from the one it started from and
## that layout becomes the board's new initial layout, so [code]R[/code] resets
## to the scrambled arrangement instead of handing the player the solved board.
##
## Place the shuffler after the board (as a later sibling in the same parent) to
## scramble synchronously during the scene's ready pass, or as a child of the
## board: it then waits for the board's [signal Node.ready] signal.

## Board to scramble. Defaults to the parent, for a shuffler nested in the board.
@export var board_path: NodePath = ^".."
## Scramble once when the scene loads.
@export var shuffle_on_ready: bool = true
## Random turns walked. 120 mixes small boards thoroughly.
@export var steps: int = 120
## 0 scrambles differently on every load; any other value is reproducible.
@export var seed: int = 0
## Only walk turns that move a void slider (primary or induced).
@export var void_only: bool = true
## Skip the immediate reverse of the previous turn when another move exists.
@export var avoid_reverse: bool = true


func _ready() -> void:
    if not shuffle_on_ready:
        return
    var board := _get_board()
    if board == null:
        push_warning("PuzzleBoardShuffler %s: board_path does not point at a PuzzleBoard." % name)
        return
    if board.is_node_ready():
        shuffle_now()
    else:
        await board.ready
        shuffle_now()


## Scramble immediately. Returns false when the board cannot be scrambled.
func shuffle_now() -> bool:
    var board := _get_board()
    if board == null:
        push_warning("PuzzleBoardShuffler %s: board_path does not point at a PuzzleBoard." % name)
        return false
    if not board.scramble(steps, seed, void_only, avoid_reverse):
        push_warning("PuzzleBoardShuffler %s: the board could not be scrambled." % name)
        return false
    return true


func _get_board() -> PuzzleBoard:
    if board_path.is_empty():
        return null
    return get_node_or_null(board_path) as PuzzleBoard
