class_name PuzzleSession
extends RefCounted

## The puzzle "brain": owns the current BoardState plus undo/redo history.
## UI and input only talk to this object.
##
## History is snapshot-based so a reset and a compound move (primary piece plus
## induced void moves) are both uniform operations.

var definition: PuzzleDefinition
var rules: PuzzleRuleSet
var current_state: BoardState
var last_turn: PuzzleTurn
var last_action: StringName = &""

var _undo_stack: Array[Dictionary] = []
var _redo_stack: Array[Dictionary] = []
var _move_count: int = 0


func _init(p_definition: PuzzleDefinition, p_rules: PuzzleRuleSet = null) -> void:
	definition = p_definition
	if p_rules != null:
		rules = p_rules
	else:
		rules = SlidingPuzzleRuleSet.new(p_definition)
	reset_initial()


## Initialize without creating a history entry. Used by _init/reset-to-new.
func reset_initial() -> void:
	current_state = _build_initial_state()
	_undo_stack.clear()
	_redo_stack.clear()
	_move_count = 0
	last_turn = null
	last_action = &""


func try_move(
	move: PuzzleMove,
	extra_blocked_cells: Array[Vector2i] = [],
	player_cell_after: Vector2i = Vector2i(-1, -1)
) -> bool:
	if rules == null:
		return false
	var turn: PuzzleTurn = rules.resolve_turn(current_state, move, extra_blocked_cells, player_cell_after)
	if turn == null or turn.is_empty():
		return false
	_undo_stack.append(_snapshot(&"move"))
	_redo_stack.clear()
	_apply_turn(turn)
	_move_count += 1
	last_turn = turn
	last_action = &"move"
	return true


## Restore the authored initial state. This is an undoable operation.
func reset() -> bool:
	if _is_at_initial_state() and _move_count == 0:
		return false
	_undo_stack.append(_snapshot(&"reset"))
	_redo_stack.clear()
	current_state = _build_initial_state()
	_move_count = 0
	last_turn = null
	last_action = &"reset"
	return true


func undo() -> bool:
	if _undo_stack.is_empty():
		return false
	_redo_stack.append(_snapshot(&"undo"))
	var snapshot: Dictionary = _undo_stack.pop_back()
	current_state = (snapshot.state as BoardState).duplicate_state()
	_move_count = int(snapshot.move_count)
	last_turn = null
	last_action = &"undo"
	return true


func redo() -> bool:
	if _redo_stack.is_empty():
		return false
	_undo_stack.append(_snapshot(&"redo"))
	var snapshot: Dictionary = _redo_stack.pop_back()
	current_state = (snapshot.state as BoardState).duplicate_state()
	_move_count = int(snapshot.move_count)
	last_turn = null
	last_action = &"redo"
	return true


func is_solved() -> bool:
	return rules != null and rules.is_solved(current_state)


func get_move_count() -> int:
	return _move_count


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


func _snapshot(kind: StringName) -> Dictionary:
	return {
		"state": current_state.duplicate_state(),
		"move_count": _move_count,
		"kind": kind,
	}


func _apply_turn(turn: PuzzleTurn) -> void:
	for move: PuzzleMove in turn.moves:
		current_state = rules.apply_move(current_state, move)


func _is_at_initial_state() -> bool:
	if definition == null:
		return true
	for i in definition.pieces.size():
		if current_state.pieces[i].cell != definition.pieces[i].initial_cell:
			return false
	return true


func _build_initial_state() -> BoardState:
	var state := BoardState.new()
	if definition == null:
		return state
	for i in definition.pieces.size():
		var piece_def: PieceDefinition = definition.pieces[i]
		state.pieces.append(PieceState.new(piece_def.id, i, piece_def.initial_cell))
	return state
