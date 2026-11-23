class_name PuzzleRuleSet
extends Resource

## Abstract rule layer. A concrete game (SlidingPuzzleRuleSet, Sokoban, ...)
## implements these without ever touching a Node.

func get_legal_moves(_state: BoardState) -> Array[PuzzleMove]:
	return []


func can_apply_move(_state: BoardState, _move: PuzzleMove, _extra_blocked_cells: Array[Vector2i] = []) -> bool:
	return false


## Resolve a primary move plus any induced moves into one atomic turn.
## Rule sets that do not support induced moves get a single-move turn based on
## their existing can_apply_move() implementation.
func resolve_turn(state: BoardState, move: PuzzleMove, extra_blocked_cells: Array[Vector2i] = [], _player_cell_after: Vector2i = Vector2i(-1, -1)) -> PuzzleTurn:
	if not can_apply_move(state, move, extra_blocked_cells):
		return null
	var turn := PuzzleTurn.new()
	turn.moves.append(move)
	return turn


## Pure application: returns a NEW state with the move applied. Callers are
## responsible for validating first via [method can_apply_move].
func apply_move(state: BoardState, move: PuzzleMove) -> BoardState:
	var result := state.duplicate_state()
	var piece := result.get_piece(move.piece_index)
	if piece != null:
		piece.cell = move.to_cell
	return result


func is_solved(_state: BoardState) -> bool:
	return false


## Optional hook: glue an extra cell (the player rider) onto a piece.
func set_rider(_piece_index: int, _offset: Vector2i) -> void:
	pass


func clear_rider() -> void:
	pass
