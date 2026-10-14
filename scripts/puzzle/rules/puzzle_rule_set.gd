class_name PuzzleRuleSet
extends Resource

## Abstract rule layer. A concrete game (SlidingPuzzleRuleSet, Sokoban, ...)
## implements these without ever touching a Node.

func get_legal_moves(_state: BoardState) -> Array[PuzzleMove]:
	return []


func can_apply_move(_state: BoardState, _move: PuzzleMove) -> bool:
	return false


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
