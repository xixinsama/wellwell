extends Node

## Source-scene contract for the bottom-left void slider in room_start_00.

const SOURCE := "res://scenes/levels/main/room_start_00.tscn"


func run() -> Array[String]:
	var failures: Array[String] = []
	var scene: PackedScene = load(SOURCE)
	if scene == null:
		failures.append("room_start_00 source scene is missing")
		return failures
	var root: Node = scene.instantiate()
	add_child(root)
	var board := root.get_node_or_null("RoomContent/Entities/PuzzleBoard")
	if board == null:
		failures.append("room_start_00 has no PuzzleBoard")
		root.free()
		return failures
	var void_piece: PuzzleTilePiece = null
	for child in board.get_children():
		if child is PuzzleTilePiece and child.is_void:
			void_piece = child as PuzzleTilePiece
			break
	if void_piece == null:
		failures.append("room_start_00 has no void slider")
	else:
		if void_piece.get_logical_cell() != Vector2i(0, 14):
			failures.append("void slider is not at the bottom-left anchor (0, 14)")
		if void_piece.shape.size() != 91:
			failures.append("void slider footprint is not 13x7 (got %d cells)" % void_piece.shape.size())
		if void_piece.get_bounds() != Rect2i(0, 0, 13, 7):
			failures.append("void slider bounds are not 13x7")
		if void_piece.x_move_distance != 13 or void_piece.y_move_distance != 7:
			failures.append("void slider distances are not 13/7")
		if void_piece.get_node_or_null("VoidTiles") == null:
			failures.append("void slider has no VoidTiles layer")
		if void_piece.get_node_or_null("VoidBody") == null:
			failures.append("void slider did not build its runtime VoidBody")
		if board.call("get_piece_at_cell", Vector2i(2, 16)) != void_piece:
			failures.append("void slider was not selectable inside its footprint")
		var normal_pick: PuzzlePiece = board.call("get_piece_at_cell", Vector2i(2, 2))
		if normal_pick == null or normal_pick == void_piece:
			failures.append("a normal slider was not selectable outside the void footprint")
		for child in board.get_children():
			if child is PuzzleTilePiece and not child.is_void:
				var anchor_pick: PuzzlePiece = board.call("get_piece_at_cell", child.get_logical_cell())
				if anchor_pick == null or anchor_pick.is_void:
					failures.append("normal slider %s was not selectable at its anchor" % child.name)
	if root.get_node_or_null("RoomContent/Entities/PuzzleBoard/VoidZone") != null:
		failures.append("room_start_00 still has the static VoidZone placeholder")
	root.free()
	return failures
