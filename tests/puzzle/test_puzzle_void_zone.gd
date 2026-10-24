extends Node

## Coverage for player-only void regions: painted cells, collision body,
## player collision-mask toggling, and the slider-mode exit guard.

const VOID_ZONE_SCRIPT := preload("res://scripts/puzzle/view/puzzle_void_zone.gd")
const PUZZLE_BOARD_SCRIPT := preload("res://scripts/puzzle/view/puzzle_board.gd")
const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const TILESET := preload("res://resources/tilesets/primordial_tileset.tres")


func run() -> Array[String]:
	var failures: Array[String] = []
	_assert_void_cells_and_body(failures)
	_assert_player_void_collision_toggle(failures)
	_assert_board_blocks_mode_exit_inside_void(failures)
	return failures


func _assert_void_cells_and_body(failures: Array[String]) -> void:
	var zone := _make_zone(Vector2i(2, 3))
	add_child(zone)
	if not bool(zone.call("has_cell", Vector2i(2, 3))):
		failures.append("void zone did not read its painted cell")
	if not bool(zone.call("has_world_position", Vector2(20.0, 28.0))):
		failures.append("void zone did not map a world position to its cell")
	if bool(zone.call("has_world_position", Vector2(4.0, 4.0))):
		failures.append("void zone reported a cell that was not painted")
	var body := zone.get_node_or_null("VoidBody") as StaticBody2D
	if body == null:
		failures.append("void zone did not build its collision body")
	elif body.collision_layer != (1 << 3) or body.collision_mask != 0:
		failures.append("void zone body is not on the player-only void layer")
	elif body.get_child_count() != 1:
		failures.append("void zone body did not get one shape per painted cell")
	zone.free()


func _assert_player_void_collision_toggle(failures: Array[String]) -> void:
	var player := PLAYER_SCENE.instantiate() as Node2D
	add_child(player)
	if (int(player.get("collision_mask")) & (1 << 3)) == 0:
		failures.append("player did not include the void layer in its collision mask")
	player.call("set_control_locked", true)
	if (int(player.get("collision_mask")) & (1 << 3)) != 0:
		failures.append("locked player still collided with the void layer")
	player.call("set_control_locked", false)
	if (int(player.get("collision_mask")) & (1 << 3)) == 0:
		failures.append("unlocked player did not restore void collision")
	player.free()


func _assert_board_blocks_mode_exit_inside_void(failures: Array[String]) -> void:
	var board := PUZZLE_BOARD_SCRIPT.new() as Node2D
	board.set("board_size", Vector2i(8, 8))
	board.set("cell_size", 8)
	board.add_child(_make_zone(Vector2i(2, 2)))
	var player := Node2D.new()
	player.name = "TestPlayer"
	player.add_to_group("player")
	add_child(player)
	add_child(board)
	board.call("set_player_to_cell", Vector2i(2, 2))
	board.call("_enter_drag_mode")
	if int(board.get("mode")) != 1:
		failures.append("board did not enter slider mode")
	board.call("_exit_drag_mode")
	if int(board.get("mode")) != 1:
		failures.append("board exited slider mode while the player was inside void")
	board.call("set_player_to_cell", Vector2i(0, 0))
	board.call("_exit_drag_mode")
	if int(board.get("mode")) != 0:
		failures.append("board stayed in slider mode after the player left void")
	board.free()
	player.free()


func _make_zone(cell: Vector2i) -> Node2D:
	var zone := VOID_ZONE_SCRIPT.new() as Node2D
	zone.name = "VoidZone"
	zone.set("cell_size", 8)
	var layer := TileMapLayer.new()
	layer.name = "VoidTiles"
	layer.tile_set = TILESET
	layer.collision_enabled = false
	layer.set_cell(cell, 0, Vector2i(0, 0))
	zone.add_child(layer)
	return zone
