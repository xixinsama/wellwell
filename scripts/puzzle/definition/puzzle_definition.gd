class_name PuzzleDefinition
extends Resource

## One complete level: board + pieces + win condition. A single .tres is a level.

@export var board: BoardDefinition
@export var pieces: Array[PieceDefinition] = []
@export var goal: GoalDefinition


func _init() -> void:
	board = BoardDefinition.new()
	goal = GoalDefinition.new()


func find_piece_index(piece_id: StringName) -> int:
	for i in pieces.size():
		if pieces[i].id == piece_id:
			return i
	return -1
