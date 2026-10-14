class_name BoardDefinition
extends Resource

## Static description of the grid a puzzle runs on.

@export var board_size: Vector2i = Vector2i(4, 5)
## Cells that can never be occupied by a piece (holes / obstacles).
@export var blocked_cells: Array[Vector2i] = []


func contains_cell(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < board_size.x and cell.y < board_size.y


func is_cell_blocked(cell: Vector2i) -> bool:
	return blocked_cells.has(cell)
