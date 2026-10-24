@tool
class_name PuzzleBoard
extends Node2D

## Runtime bridge between the two operation cores.
##
## Jump mode: the player keeps full platforming control and the board is idle.
## Drag mode: the player is locked and rides the block it is standing on.
##
## Two ways to move a block:
##  - Click a block to select it (stays selected), then press the movement keys
##    (WASD / arrows) to slide it one cell per press.
##  - Press and hold a block and drag one cell in a direction; a dashed outline
##    previews the target and releasing commits the move or flashes red.

enum ControlMode { JUMP, DRAG }

@export var board_size: Vector2i = Vector2i(8, 4):
	set(value):
		board_size = Vector2i(maxi(1, value.x), maxi(1, value.y))
		queue_redraw()
@export var cell_size: int = 8:
	set(value):
		cell_size = maxi(1, value)
		queue_redraw()
@export var switch_action: StringName = &"switch_mode"
@export var player_group: StringName = &"player"
@export var undo_action: StringName = &"undo"
@export var reset_action: StringName = &"reset"
## Static board walls. Sliders and the void target validation respect these.
@export var blocked_cells: Array[Vector2i] = []
## Optional child defining cells that only the player collides with in jump mode.
@export var void_zone_path: NodePath = ^"VoidZone"

const DRAG_THRESHOLD_PX := 4.0
const DRAG_ANIMATION_SECONDS := 0.08

var session: PuzzleSession
var definition: PuzzleDefinition
var mode: ControlMode = ControlMode.JUMP

var _pieces: Array[PuzzlePiece] = []
var _player: Node2D = null
var _void_zone: PuzzleVoidZone = null
var _mode_overlay: PuzzleModeOverlay = null
var _target_preview: PuzzleTargetPreview = null
var _piece_tweens: Dictionary = {}

var _attached_piece: PuzzlePiece = null
var _attached_offset: Vector2 = Vector2.ZERO
var _carried_during_drag: bool = false

var _selected_piece: PuzzlePiece = null
var _mouse_was_down: bool = false
var _drag_start_local: Vector2 = Vector2.ZERO
var _dragging: bool = false
var _drag_direction: Vector2i = Vector2i.ZERO


func _ready() -> void:
	if Engine.is_editor_hint():
		queue_redraw()
		return
	_build_session_from_scene_pieces()
	_resolve_player_lazy()
	_resolve_void_zone()
	_build_target_preview()
	_build_mode_overlay()


func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	var rect := Rect2(Vector2.ZERO, Vector2(board_size) * float(cell_size))
	draw_rect(rect, Color(0.45, 0.75, 1.0, 0.12), true)
	draw_rect(rect, Color(0.45, 0.75, 1.0, 0.65), false, 1.0)
	var line_color := Color(0.45, 0.75, 1.0, 0.22)
	for x in range(1, board_size.x):
		draw_line(Vector2(x * cell_size, 0.0), Vector2(x * cell_size, rect.size.y), line_color)
	for y in range(1, board_size.y):
		draw_line(Vector2(0.0, y * cell_size), Vector2(rect.size.x, y * cell_size), line_color)


func _exit_tree() -> void:
	# Never leave the player locked if the board is streamed out mid-drag.
	if mode == ControlMode.DRAG:
		_exit_drag_mode(true)


func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if session == null:
		return
	_resolve_player_lazy()
	if _handle_history_input(
		Input.is_action_just_pressed(String(undo_action)),
		Input.is_action_just_pressed(String(reset_action))
	):
		return
	if Input.is_action_just_pressed(String(switch_action)):
		if mode == ControlMode.JUMP:
			_enter_drag_mode()
		else:
			_exit_drag_mode()
	_handle_mouse()
	if mode == ControlMode.DRAG:
		_handle_move_keys()


func _physics_process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return
	_follow_attached_piece()


# --- Construction -------------------------------------------------------------

func _build_session_from_scene_pieces() -> void:
	_pieces.clear()
	session = null

	definition = PuzzleDefinition.new()
	definition.board = BoardDefinition.new()
	definition.board.board_size = board_size
	definition.board.blocked_cells = blocked_cells.duplicate()
	definition.goal = GoalDefinition.new()

	var index := 0
	for child in get_children():
		if child is PuzzlePiece:
			var piece_node := child as PuzzlePiece
			piece_node.cell_size = cell_size
			piece_node.piece_index = index
			_pieces.append(piece_node)

			var piece_def := PieceDefinition.new()
			piece_def.id = StringName("piece_%d" % index)
			piece_def.shape = piece_node.shape
			piece_def.wall_shape = piece_node.wall_shape.duplicate()
			piece_def.one_way_shape = piece_node.one_way_shape.duplicate()
			piece_def.is_void = piece_node.is_void
			piece_def.enable = piece_node.enable
			piece_def.initial_cell = piece_node.get_logical_cell()
			piece_def.movement_mode = piece_node.movement_mode
			piece_def.x_move_distance = piece_node.x_move_distance
			piece_def.y_move_distance = piece_node.y_move_distance
			piece_def.color = piece_node.color
			definition.pieces.append(piece_def)
			index += 1

	session = PuzzleSession.new(definition)


func _resolve_player_lazy() -> void:
	if _player != null and is_instance_valid(_player):
		return
	var candidates := get_tree().get_nodes_in_group(String(player_group))
	_player = candidates[0] as Node2D if not candidates.is_empty() else null


func _build_target_preview() -> void:
	_target_preview = PuzzleTargetPreview.new()
	_target_preview.name = "TargetPreview"
	_target_preview.setup(cell_size)
	add_child(_target_preview)


func _build_mode_overlay() -> void:
	_mode_overlay = PuzzleModeOverlay.new()
	_mode_overlay.name = "ModeOverlay"
	_mode_overlay.setup(cell_size, _pieces)
	_mode_overlay.set_active(false)
	add_child(_mode_overlay)


# --- Mode switching -----------------------------------------------------------

func _enter_drag_mode() -> void:
	mode = ControlMode.DRAG
	_carried_during_drag = false
	_lock_player(true)
	if _mode_overlay != null:
		_mode_overlay.set_active(true)


func _exit_drag_mode(force: bool = false) -> void:
	if not force and (_player_cell_inside_void() or _player_cell_inside_piece()):
		return
	var grant_air_jump := _carried_during_drag and not force
	_carried_during_drag = false
	mode = ControlMode.JUMP
	_deselect_piece(force)
	_end_drag()
	_detach_player()
	_lock_player(false)
	if grant_air_jump:
		_grant_air_jump_to_player()
	if _mode_overlay != null:
		_mode_overlay.set_active(false)


func _grant_air_jump_to_player() -> void:
	if _player == null or not is_instance_valid(_player):
		return
	if _player.has_method("grant_air_jump"):
		_player.call("grant_air_jump")


func _lock_player(locked: bool) -> void:
	if _player == null or not is_instance_valid(_player):
		return
	if _player.has_method("set_control_locked"):
		_player.set_control_locked(locked)
	else:
		_player.set_physics_process(not locked)


func _resolve_void_zone() -> void:
	_void_zone = get_node_or_null(void_zone_path) as PuzzleVoidZone


func _player_cell_inside_void() -> bool:
	if _player == null or not is_instance_valid(_player):
		return false
	var cell := player_cell_from_world()
	if _void_zone != null and is_instance_valid(_void_zone):
		var top_left := _player.global_position + Vector2(-4.0, -8.0)
		if _void_zone.has_world_position(top_left):
			return true
	for piece in _pieces:
		if piece.is_void and piece.shape.has(cell - piece.get_logical_cell()):
			return true
	return false


func _player_cell_inside_piece() -> bool:
	if _player == null or not is_instance_valid(_player):
		return false
	var cell := player_cell_from_world()
	for piece in _pieces:
		if piece.shape.has(cell - piece.get_logical_cell()):
			return true
	return false


func _is_player_inside_board_rect() -> bool:
	if _player == null or not is_instance_valid(_player):
		return false
	return Rect2i(Vector2i.ZERO, board_size).has_point(player_cell_from_world())


func _detach_player() -> void:
	_attached_piece = null


func _follow_attached_piece() -> void:
	if _attached_piece == null or not is_instance_valid(_attached_piece):
		_attached_piece = null
		return
	if _player == null or not is_instance_valid(_player):
		return
	_player.global_position = _attached_piece.global_position + _attached_offset


## The player is an 8x8 block: its origin is its bottom-centre, so its top-left
## corner sits at (-4, -8) in local space.
func player_cell_from_world() -> Vector2i:
	if _player == null or not is_instance_valid(_player):
		return Vector2i.ZERO
	var top_left := _player.global_position + Vector2(-4.0, -8.0)
	var local := to_local(top_left)
	return Vector2i(roundi(local.x / float(cell_size)), roundi(local.y / float(cell_size)))


func set_player_to_cell(cell: Vector2i) -> void:
	if _player == null or not is_instance_valid(_player):
		return
	_player.global_position = to_global(cell_to_world(cell)) + Vector2(4.0, 8.0)


## Whether the player rides [param piece]. Two cases:
##  1. the player stands on the piece (the cell under its feet belongs to it);
##  2. the player's cell lies inside the piece's minimal bounding rect.
func _player_rides(piece: PuzzlePiece) -> bool:
	if _player == null or not is_instance_valid(_player):
		return false
	if piece.is_void:
		return false
	var player_cell := player_cell_from_world()
	var support_offset := player_cell + Vector2i.DOWN - piece.get_logical_cell()
	if piece.shape.has(support_offset):
		return true
	return _piece_rect(piece, piece.get_logical_cell()).has_point(player_cell)


## Snaps the player to the nearest world grid cell (smallest displacement).
func _snap_player_to_nearest_cell() -> void:
	if _player == null or not is_instance_valid(_player):
		return
	set_player_to_cell(player_cell_from_world())


func _attach_player_to(piece: PuzzlePiece) -> void:
	_snap_player_to_nearest_cell()
	_attached_piece = piece
	_attached_offset = _player.global_position - piece.global_position


## Registers the player as an extra cell glued to [param piece] so the piece's
## own move is checked with it and other pieces are blocked by it.
func _register_rider(piece: PuzzlePiece) -> void:
	if session == null:
		return
	var offset := player_cell_from_world() - piece.get_logical_cell()
	session.set_rider(piece.piece_index, offset)


func _piece_rect(piece: PuzzlePiece, anchor_cell: Vector2i) -> Rect2i:
	var bounds := piece.get_bounds()
	return Rect2i(anchor_cell + bounds.position, bounds.size)


func _piece_move_distance(piece: PuzzlePiece, direction: Vector2i) -> int:
	if definition == null or piece.piece_index < 0 or piece.piece_index >= definition.pieces.size():
		return 1
	return definition.pieces[piece.piece_index].get_move_distance(direction)


# --- Selection & movement -----------------------------------------------------

func _handle_mouse() -> void:
	var down := Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	if down and not _mouse_was_down:
		var local := to_local(get_global_mouse_position())
		var cell := _local_to_cell(local)
		var piece := get_piece_at_cell(cell)
		if piece != null and _can_drag_piece(piece):
			if mode == ControlMode.JUMP:
				_enter_drag_mode()
			_select_piece(piece)
			_drag_start_local = local
			_dragging = false
			_drag_direction = Vector2i.ZERO
			_hide_preview()
		else:
			_deselect_piece()
	elif down and _selected_piece != null:
		var local := to_local(get_global_mouse_position())
		if not _dragging:
			var delta := local - _drag_start_local
			if maxf(absf(delta.x), absf(delta.y)) >= DRAG_THRESHOLD_PX:
				var direction := _dominant_direction(delta)
				if _piece_allows_axis(_selected_piece.piece_index, direction):
					_dragging = true
					_drag_direction = direction
		if _dragging:
			var target := _selected_piece.get_logical_cell() + _drag_direction * _piece_move_distance(_selected_piece, _drag_direction)
			_show_preview(_selected_piece, target)
	elif not down and _mouse_was_down:
		if _dragging and _selected_piece != null:
			_move_piece_to(_selected_piece, _drag_direction)
		_end_drag()
	_mouse_was_down = down


func _select_piece(piece: PuzzlePiece) -> void:
	if not _can_drag_piece(piece):
		return
	if _selected_piece == piece:
		return
	if _player_cell_inside_void() and _attached_piece != null and piece != _attached_piece:
		return
	_deselect_piece()
	_selected_piece = piece
	if _mode_overlay != null:
		_mode_overlay.set_selected(piece)
	if piece.is_void:
		return
	if _player_rides(piece):
		_attach_player_to(piece)
		_register_rider(piece)


func _deselect_piece(force: bool = false) -> void:
	if not force and _player_cell_inside_void() and _attached_piece != null:
		return
	_selected_piece = null
	if _mode_overlay != null:
		_mode_overlay.set_selected(null)
	_detach_player()
	if session != null:
		session.clear_rider()


func _end_drag() -> void:
	_dragging = false
	_drag_direction = Vector2i.ZERO


func _handle_move_keys() -> void:
	if _selected_piece == null or not is_instance_valid(_selected_piece):
		return
	var direction := Vector2i.ZERO
	if Input.is_action_just_pressed("move_left"):
		direction = Vector2i.LEFT
	elif Input.is_action_just_pressed("move_right"):
		direction = Vector2i.RIGHT
	elif Input.is_action_just_pressed("move_up"):
		direction = Vector2i.UP
	elif Input.is_action_just_pressed("move_down"):
		direction = Vector2i.DOWN
	if direction == Vector2i.ZERO:
		return
	_move_piece_to(_selected_piece, direction)


func _move_piece_to(piece: PuzzlePiece, direction: Vector2i) -> void:
	if piece == null or not is_instance_valid(piece):
		return
	if direction == Vector2i.ZERO:
		return
	if not _can_drag_piece(piece):
		return
	var from := piece.get_logical_cell()
	var distance := _piece_move_distance(piece, direction)
	var target := from + direction * distance
	if not _piece_allows_axis(piece.piece_index, direction):
		_flash_invalid(piece, target)
		return
	# The player rides a block when it stands on it or its cell is inside the
	# block's bounding rect. A rider is glued onto the block (its own extra
	# cell); otherwise the player is an independent wall for the block.
	var riding := _player_rides(piece)
	var extra_blocked: Array[Vector2i] = []
	if riding:
		_register_rider(piece)
	else:
		if session != null:
			session.clear_rider()
		extra_blocked.append(player_cell_from_world())
	var player_after := player_cell_from_world()
	if riding:
		player_after += target - from
	var move := PuzzleMove.new(piece.piece_index, from, target)
	if session != null and session.try_move(move, extra_blocked, player_after):
		if riding:
			_carried_during_drag = true
			_attach_player_to(piece)
		_sync_pieces_from_state(true)
		_hide_preview()
	else:
		_flash_invalid(piece, target)


func _can_drag_piece(piece: PuzzlePiece) -> bool:
	if piece == null or definition == null or piece.piece_index < 0 or piece.piece_index >= definition.pieces.size():
		return false
	return piece.enable and definition.pieces[piece.piece_index].is_controllable()


func _piece_allows_axis(piece_index: int, axis: Vector2i) -> bool:
	if definition == null or piece_index < 0 or piece_index >= definition.pieces.size():
		return false
	return definition.pieces[piece_index].allows_axis(axis)


func _dominant_direction(delta: Vector2) -> Vector2i:
	if absf(delta.x) >= absf(delta.y):
		return Vector2i.RIGHT if delta.x >= 0.0 else Vector2i.LEFT
	return Vector2i.DOWN if delta.y >= 0.0 else Vector2i.UP


# --- View sync ----------------------------------------------------------------

## Scope Z/R to a board whose rectangle contains the player. Undo is checked
## first so pressing both keys in one frame never resets after a failed undo.
func _handle_history_input(undo_pressed: bool, reset_pressed: bool) -> bool:
	if mode != ControlMode.DRAG or not _is_player_inside_board_rect():
		return false
	if undo_pressed:
		_undo()
		return true
	if reset_pressed:
		_reset_puzzle()
		return true
	return false


func _undo() -> void:
	if session == null or not session.undo():
		return
	_end_drag()
	_hide_preview()
	_sync_pieces_from_state(true)


func _reset_puzzle() -> void:
	if session == null or not session.reset():
		return
	_deselect_piece(true)
	_end_drag()
	_hide_preview()
	_sync_pieces_from_state(true)


func _kill_piece_tween(piece_index: int) -> void:
	var tween: Tween = _piece_tweens.get(piece_index)
	if tween != null and tween.is_valid():
		tween.kill()
	_piece_tweens.erase(piece_index)


func _sync_pieces_from_state(animate: bool) -> void:
	if session == null:
		return
	for i in _pieces.size():
		var piece := _pieces[i]
		var state := session.current_state.get_piece(i)
		if state == null:
			continue
		piece.logical_cell = state.cell
		var target := piece.cell_to_world(state.cell)
		_kill_piece_tween(i)
		if animate and piece.position.distance_to(target) > 0.01:
			var tween := create_tween()
			tween.tween_property(piece, "position", target, DRAG_ANIMATION_SECONDS)
			_piece_tweens[i] = tween
		else:
			piece.position = target


func _show_preview(piece: PuzzlePiece, target_anchor_cell: Vector2i) -> void:
	if _target_preview == null:
		return
	var bounds := piece.get_bounds()
	_target_preview.show_at(target_anchor_cell + bounds.position, bounds.size)


func _flash_invalid(piece: PuzzlePiece, target_anchor_cell: Vector2i) -> void:
	if _target_preview == null:
		return
	var bounds := piece.get_bounds()
	_target_preview.show_at(target_anchor_cell + bounds.position, bounds.size)
	_target_preview.set_invalid()
	var tween := create_tween()
	tween.tween_property(_target_preview, "modulate:a", 0.15, 0.07)
	tween.tween_property(_target_preview, "modulate:a", 1.0, 0.07)
	tween.tween_property(_target_preview, "modulate:a", 0.15, 0.07)
	tween.tween_property(_target_preview, "modulate:a", 1.0, 0.07)
	tween.tween_callback(_hide_preview)


func _hide_preview() -> void:
	if _target_preview != null:
		_target_preview.modulate = Color.WHITE
		_target_preview.hide_preview()


# --- Queries ------------------------------------------------------------------

func get_piece_at_cell(cell: Vector2i) -> PuzzlePiece:
	# When pieces overlap in a one-way cell, the platform is drawn above the
	# wall, so selecting it matches what the player sees. Among overlapping
	# one-way pieces, the last one in tree order is the topmost layer.
	var fallback: PuzzlePiece = null
	var one_way_pick: PuzzlePiece = null
	var void_pick: PuzzlePiece = null
	for piece in _pieces:
		var offset := cell - piece.get_logical_cell()
		if piece.is_void:
			# Only the cells actually painted as void are selectable; a void
			# piece elsewhere on the board must not steal clicks from other
			# pieces.
			if piece.shape.has(offset):
				void_pick = piece
		elif piece.one_way_shape.has(offset):
			one_way_pick = piece
		elif fallback == null and piece.shape.has(offset):
			fallback = piece
	if void_pick != null:
		return void_pick
	return one_way_pick if one_way_pick != null else fallback


func world_to_cell(world_pos: Vector2) -> Vector2i:
	var local := to_local(world_pos)
	return Vector2i(floori(local.x / float(cell_size)), floori(local.y / float(cell_size)))


func cell_to_world(cell: Vector2i) -> Vector2:
	return Vector2(cell) * float(cell_size)


func _local_to_cell(local: Vector2) -> Vector2i:
	return Vector2i(floori(local.x / float(cell_size)), floori(local.y / float(cell_size)))
