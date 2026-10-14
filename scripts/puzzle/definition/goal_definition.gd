class_name GoalDefinition
extends Resource

## Win condition for a puzzle. Kept data-driven instead of hard-coded.

@export var piece_id: StringName = &""
## Top-left cell the piece must reach when [member target_area] is empty.
@export var target_cell: Vector2i = Vector2i.ZERO
## Optional region: when its size is positive the piece only needs to enter it.
@export var target_area: Rect2i = Rect2i()


func is_satisfied(state: BoardState) -> bool:
	if state == null:
		return false
	var piece_index := state.find_piece_index(piece_id)
	if piece_index < 0:
		return false
	var cell := state.pieces[piece_index].cell
	if target_area.size.x > 0 and target_area.size.y > 0:
		return target_area.has_point(cell)
	return cell == target_cell
