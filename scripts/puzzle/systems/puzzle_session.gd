class_name PuzzleSession
extends RefCounted

## The puzzle "brain": owns the current BoardState plus undo/redo history.
## UI and input only talk to this object.

var definition: PuzzleDefinition
var rules: PuzzleRuleSet
var current_state: BoardState
var move_history: Array[PuzzleMove] = []
var redo_history: Array[PuzzleMove] = []


func _init(p_definition: PuzzleDefinition, p_rules: PuzzleRuleSet = null) -> void:
	definition = p_definition
	if p_rules != null:
		rules = p_rules
	else:
		rules = SlidingPuzzleRuleSet.new(p_definition)
	reset()


func reset() -> void:
	current_state = _build_initial_state()
	move_history.clear()
	redo_history.clear()


func try_move(move: PuzzleMove, extra_blocked_cells: Array[Vector2i] = []) -> bool:
	if rules == null or not rules.can_apply_move(current_state, move, extra_blocked_cells):
		return false
	current_state = rules.apply_move(current_state, move)
	move_history.append(move)
	redo_history.clear()
	return true


func undo() -> bool:
	if move_history.is_empty():
		return false
	var move: PuzzleMove = move_history.pop_back()
	redo_history.append(move)
	current_state = rules.apply_move(current_state, move.get_inverse())
	return true


func redo() -> bool:
	if redo_history.is_empty():
		return false
	var move: PuzzleMove = redo_history.pop_back()
	move_history.append(move)
	current_state = rules.apply_move(current_state, move)
	return true


func is_solved() -> bool:
	return rules != null and rules.is_solved(current_state)


func get_move_count() -> int:
	return move_history.size()


func get_legal_moves() -> Array[PuzzleMove]:
	if rules == null:
		return []
	return rules.get_legal_moves(current_state)


## Register the player as an extra cell glued to [param piece_index].
func set_rider(piece_index: int, offset: Vector2i) -> void:
	if rules != null:
		rules.set_rider(piece_index, offset)


func clear_rider() -> void:
	if rules != null:
		rules.clear_rider()


func _build_initial_state() -> BoardState:
	var state := BoardState.new()
	if definition == null:
		return state
	for i in definition.pieces.size():
		var piece_def: PieceDefinition = definition.pieces[i]
		state.pieces.append(PieceState.new(piece_def.id, i, piece_def.initial_cell))
	return state
