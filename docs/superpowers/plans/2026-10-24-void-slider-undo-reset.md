# Void Slider and Puzzle Undo/Reset Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **Status:** Implemented and verified on 2026-10-24. The working tree is left
> uncommitted because it contains earlier user/agent changes; use the test
> files listed in the design spec's Implementation Notes. The original
> per-task commit steps are intentionally not applied.
>
> **Verification:** `godot --headless --path . -s res://tests/run_runtime_suite.gd`
> exited 0 twice consecutively after the final changes; `godot --headless
> --editor --path . --quit` and `tools/validate_project.gd` also exited 0. The
> only output is the existing Area2D/shape/RID leak noise and the known
> `world_root.tscn` invalid-UID warning.

**Goal:** Add a movable void slider whose min rectangle can be pushed by a covering piece (A+ atomic rule), plus board-local undo (Z) and reset (R) where reset is undoable.

**Architecture:** A void piece is a `PuzzleTilePiece` whose `VoidTiles` layer defines a pass-through footprint and a player-only collision body. A move resolves into a `PuzzleTurn` containing the primary move and induced void moves. `PuzzleSession` stores full board snapshots so moves, reset, and undo/redo are uniform. `PuzzleBoard` syncs all pieces from the snapshot and applies Z/R only to boards containing the player.

**Tech Stack:** Godot 4.7, GDScript, `TileMapLayer`, `StaticBody2D`, `PuzzleSession`, headless runtime suite.

---

## File Structure

- Create: `scripts/puzzle/core/puzzle_turn.gd` — compound move record.
- Create: `tests/puzzle/test_void_slider_rules.gd` — A+ pure rules.
- Create: `tests/puzzle/test_puzzle_history.gd` — session/board undo/reset.
- Modify: `scripts/puzzle/definition/piece_definition.gd` — `is_void`.
- Modify: `scripts/puzzle/view/puzzle_piece.gd` — `is_void`.
- Modify: `scripts/puzzle/view/puzzle_tile_piece.gd` — `VoidTiles`, `VoidBody`.
- Modify: `scripts/puzzle/core/board_occupancy.gd` — void pass-through.
- Modify: `scripts/puzzle/rules/puzzle_rule_set.gd` — default `resolve_turn`.
- Modify: `scripts/puzzle/rules/sliding_puzzle_rule_set.gd` — A+ turn resolver.
- Modify: `scripts/puzzle/systems/puzzle_session.gd` — snapshots and turns.
- Modify: `scripts/puzzle/view/puzzle_board.gd` — turn sync, V selection/guard, Z/R.
- Modify: `scripts/player/player_controller.gd` / `scenes/player/player.tscn` — already have void mask; verify.
- Modify: `project.godot` — `undo` Z, `reset` R.
- Modify: `scenes/levels/main/room_start_00.tscn` — bottom-left void piece; remove empty static VoidZone.
- Modify: `tests/puzzle/test_puzzle_tile_piece.gd` — void tile piece coverage.
- Modify: `tests/puzzle/test_puzzle_room_contract.gd` — room start? New source contract.
- Modify: `tests/runtime_suite.gd` — register new tests.
- Modify: `docs/extension-guide.md` and `游戏机制设计.md` — rules.

---

### Task 1: Add `is_void` to the piece model and detect `VoidTiles`

**Files:**
- Modify: `scripts/puzzle/definition/piece_definition.gd`
- Modify: `scripts/puzzle/view/puzzle_piece.gd`
- Modify: `scripts/puzzle/view/puzzle_tile_piece.gd`
- Test: `tests/puzzle/test_puzzle_tile_piece.gd`

- [ ] **Step 1: Write a failing test for a void tile piece**

Add to `tests/puzzle/test_puzzle_tile_piece.gd`:

```gdscript
func _assert_void_tile_piece(failures: Array[String]) -> void:
	var piece := TILE_PIECE_SCRIPT.new() as PuzzleTilePiece
	piece.cell_size = 8
	var void_layer := _make_layer("VoidTiles", false)
	void_layer.set_cell(Vector2i(0, 0), 0, Vector2i(0, 0))
	void_layer.set_cell(Vector2i(1, 0), 0, Vector2i(0, 0))
	piece.add_child(void_layer)
	add_child(piece)
	if not piece.is_void:
		failures.append("VoidTiles piece was not marked void")
	if piece.shape.size() != 2 or not piece.wall_shape.is_empty():
		failures.append("void piece footprint was not the painted void cells")
	var body := piece.get_node_or_null("VoidBody") as StaticBody2D
	if body == null or body.collision_layer != (1 << 3) or body.get_child_count() != 2:
		failures.append("void piece did not build a player-only body")
	piece.free()
```

Call `_assert_void_tile_piece(failures)` from `run()`.

- [ ] **Step 2: Run the suite and confirm the new test fails**

Run: `godot --headless --path . -s res://tests/run_runtime_suite.gd`
Expected: FAIL because `is_void`/`VoidTiles` handling does not exist.

- [ ] **Step 3: Add the data fields and tile detection**

In `PieceDefinition`:

```gdscript
@export var is_void: bool = false
```

In `PuzzlePiece`:

```gdscript
var is_void: bool = false
```

In `PuzzleTilePiece`:

```gdscript
const VOID_LAYER_NAME := "VoidTiles"
var _void_layer: TileMapLayer = null
```

Replace the collision-layer collection with a tile-layer collection that also
finds `VoidTiles`:

```gdscript
func _collect_tile_layers() -> void:
    _collision_layers.clear()
    _void_layer = null
    for child: Node in get_children():
        var layer := child as TileMapLayer
        if layer == null:
            continue
        if layer.name == VOID_LAYER_NAME:
            _void_layer = layer
        elif layer.collision_enabled:
            _collision_layers.append(layer)


func _is_tile_piece() -> bool:
    return _void_layer != null or not _collision_layers.is_empty()
```

Use `_collect_tile_layers()`/`_is_tile_piece()` instead of
`_collect_collision_layers()` and the direct `_collision_layers.is_empty()`
checks in `_ready`, `_process`, `_draw`, `_refresh_from_polygon`,
`_build_collision`, `set_highlight`, and configuration warnings.

In `_refresh_from_polygon()`, after collecting wall/one-way cells, add:

```gdscript
    var void_cells: Array[Vector2i] = []
    if _void_layer != null:
        void_cells.assign(_void_layer.get_used_cells())
    if not void_cells.is_empty():
        is_void = true
        for layer: TileMapLayer in _collision_layers:
            layer.collision_enabled = false
        shape = void_cells
        shape.sort_custom(_cell_comes_before)
        wall_shape.clear()
        one_way_shape.clear()
        _rebuild_void_body()
        _layer_signature = _compute_layer_signature()
        _update_highlight()
        queue_redraw()
        return
    is_void = false
    _clear_void_body()
    # existing wall/one-way shape assignment continues here
```

Add the void body builder:

```gdscript
func _rebuild_void_body() -> void:
    _clear_void_body()
    if not is_void or shape.is_empty():
        return
    var body := StaticBody2D.new()
    body.name = "VoidBody"
    body.collision_layer = 1 << 3
    body.collision_mask = 0
    add_child(body)
    for cell: Vector2i in shape:
        var collision := CollisionShape2D.new()
        var rect := RectangleShape2D.new()
        rect.size = Vector2(cell_size, cell_size)
        collision.shape = rect
        collision.position = (Vector2(cell) + Vector2(0.5, 0.5)) * float(cell_size)
        body.add_child(collision)


func _clear_void_body() -> void:
    var old := get_node_or_null("VoidBody")
    if old != null:
        old.free()
```

- [ ] **Step 4: Run the suite and confirm it passes**

Run: `godot --headless --path . -s res://tests/run_runtime_suite.gd`
Expected: exit code 0.

- [ ] **Step 5: Commit the task**

```bash
git add scripts/puzzle/definition/piece_definition.gd scripts/puzzle/view/puzzle_piece.gd scripts/puzzle/view/puzzle_tile_piece.gd tests/puzzle/test_puzzle_tile_piece.gd
git commit -m "feat: add void tile piece footprint and player body"
```

---

### Task 2: Void pass-through occupancy and A+ turn resolver

**Files:**
- Create: `scripts/puzzle/core/puzzle_turn.gd`
- Modify: `scripts/puzzle/core/board_occupancy.gd`
- Modify: `scripts/puzzle/rules/puzzle_rule_set.gd`
- Modify: `scripts/puzzle/rules/sliding_puzzle_rule_set.gd`
- Test: `tests/puzzle/test_void_slider_rules.gd`

- [ ] **Step 1: Write failing A+ rule tests**

Create `tests/puzzle/test_void_slider_rules.gd` with helpers that build a wall
piece and a void piece:

```gdscript
const BoardOccupancy := preload("res://scripts/puzzle/core/board_occupancy.gd")
const PieceDefinition := preload("res://scripts/puzzle/definition/piece_definition.gd")
const PuzzleDefinition := preload("res://scripts/puzzle/definition/puzzle_definition.gd")
const PuzzleMove := preload("res://scripts/puzzle/core/puzzle_move.gd")
const PuzzleSession := preload("res://scripts/puzzle/systems/puzzle_session.gd")
const SlidingPuzzleRuleSet := preload("res://scripts/puzzle/rules/sliding_puzzle_rule_set.gd")

func _wall(id: StringName, cell: Vector2i, cells: Array[Vector2i]) -> PieceDefinition:
    var p := PieceDefinition.new()
    p.id = id
    p.shape = cells.duplicate()
    p.wall_shape = cells.duplicate()
    p.initial_cell = cell
    return p

func _void(id: StringName, cell: Vector2i, cells: Array[Vector2i]) -> PieceDefinition:
    var p := PieceDefinition.new()
    p.id = id
    p.is_void = true
    p.shape = cells.duplicate()
    p.initial_cell = cell
    return p
```

Required cases:

1. Hollow mover min rect covers solid V and V target is free:
   the resolver returns a turn with 2 moves; V target is opposite by the full
   delta.
2. Partial min-rect overlap returns no induced V move.
3. V target lands on a `blocked_cells` wall: the resolver returns `null`.
4. V target overlaps another normal piece: allowed.
5. V target equals the player's post-move cell: `null`.
6. Void primary move ignores normal pieces but is blocked by `blocked_cells`.
7. A large mover still covering V after V moves produces exactly one V move.

- [ ] **Step 2: Run the suite and confirm failures**

Run: `godot --headless --path . -s res://tests/run_runtime_suite.gd`
Expected: failures for missing `is_void` occupancy/resolver behavior.

- [ ] **Step 3: Create `PuzzleTurn`**

Create `scripts/puzzle/core/puzzle_turn.gd`:

```gdscript
class_name PuzzleTurn
extends RefCounted

## A primary move plus every void move induced by it.
var moves: Array[PuzzleMove] = []


func add(piece_index: int, from_cell: Vector2i, to_cell: Vector2i) -> void:
    moves.append(PuzzleMove.new(piece_index, from_cell, to_cell))


func is_empty() -> bool:
    return moves.is_empty()
```

- [ ] **Step 4: Teach occupancy about void pieces**

In `BoardOccupancy`:

```gdscript
func get_piece_wall_offsets(piece_index: int) -> Array[Vector2i]:
    var offsets: Array[Vector2i] = []
    if definition == null or piece_index < 0 or piece_index >= definition.pieces.size():
        return offsets
    var piece := definition.pieces[piece_index]
    if piece.is_void:
        return offsets
    # existing wall fallback and extras
```

```gdscript
func get_piece_one_way_offsets(piece_index: int) -> Array[Vector2i]:
    var offsets: Array[Vector2i] = []
    if definition == null or piece_index < 0 or piece_index >= definition.pieces.size():
        return offsets
    var piece := definition.pieces[piece_index]
    if piece.is_void:
        return offsets
    # existing fallback
```

```gdscript
func get_piece_offsets(piece_index: int) -> Array[Vector2i]:
    var offsets: Array[Vector2i] = []
    if definition == null or piece_index < 0 or piece_index >= definition.pieces.size():
        return offsets
    var piece := definition.pieces[piece_index]
    if piece.is_void:
        _append_unique(offsets, piece.shape)
        return offsets
    _append_unique(offsets, get_piece_wall_offsets(piece_index))
    _append_unique(offsets, get_piece_one_way_offsets(piece_index))
    return offsets
```

In `can_place_piece`, skip void pieces when building other cell sets:

```gdscript
    var moving_is_void := definition.pieces[piece_index].is_void
    for other in state.pieces:
        if other.piece_index == ignore_piece_index or other.piece_index == piece_index:
            continue
        if definition.pieces[other.piece_index].is_void:
            continue
        # existing wall/one-way collection
```

For target check, only apply other cell sets when the mover is not void:

```gdscript
        if not moving_is_void:
            if other_wall_cells.has(occupied):
                return false
            if other_one_way_cells.has(occupied) and not current_cells.has(occupied):
                if step == ONE_WAY_BLOCKED_ENTRY:
                    return false
```

- [ ] **Step 5: Add the default `resolve_turn` hook**

In `PuzzleRuleSet`:

```gdscript
func resolve_turn(state: BoardState, move: PuzzleMove, extra_blocked_cells: Array[Vector2i] = [], _player_cell_after: Vector2i = Vector2i(-1, -1)) -> PuzzleTurn:
    if not can_apply_move(state, move, extra_blocked_cells):
        return null
    var turn := PuzzleTurn.new()
    turn.moves.append(move)
    return turn
```

- [ ] **Step 6: Implement A+ in `SlidingPuzzleRuleSet`**

Rename the current `can_apply_move` body to `_can_apply_primary`. Make
`can_apply_move` resolve the turn:

```gdscript
func can_apply_move(state: BoardState, move: PuzzleMove, extra_blocked_cells: Array[Vector2i] = []) -> bool:
    var turn := resolve_turn(state, move, extra_blocked_cells)
    return turn != null and not turn.is_empty()
```

Add:

```gdscript
func resolve_turn(
    state: BoardState,
    move: PuzzleMove,
    extra_blocked_cells: Array[Vector2i] = [],
    player_cell_after: Vector2i = Vector2i(-1, -1)
) -> PuzzleTurn:
    if not _can_apply_primary(state, move, extra_blocked_cells):
        return null
    var turn := PuzzleTurn.new()
    turn.moves.append(move)
    var primary := definition.pieces[move.piece_index]
    if primary.is_void:
        return turn
    var delta := move.to_cell - move.from_cell
    var mover_bounds := _shifted_bounds(primary, move.to_cell)
    for i in definition.pieces.size():
        var candidate := definition.pieces[i]
        if not candidate.is_void:
            continue
        var v_bounds := _shifted_bounds(candidate, state.pieces[i].cell)
        if not mover_bounds.encloses(v_bounds):
            continue
        var target := state.pieces[i].cell - delta
        if not _can_place_void_piece(state, i, target, extra_blocked_cells, player_cell_after):
            return null
        turn.moves.append(PuzzleMove.new(i, state.pieces[i].cell, target))
    return turn


func _shifted_bounds(piece: PieceDefinition, cell: Vector2i) -> Rect2i:
    var bounds := piece.get_bounds()
    return Rect2i(cell + bounds.position, bounds.size)


func _can_place_void_piece(
    state: BoardState,
    piece_index: int,
    target: Vector2i,
    extra_blocked_cells: Array[Vector2i],
    player_cell_after: Vector2i
) -> bool:
    var occupancy := _get_occupancy()
    if occupancy == null:
        return false
    for cell: Vector2i in occupancy.get_occupied_cells(piece_index, target):
        if not occupancy.is_cell_inside_board(cell):
            return false
        if occupancy.is_cell_blocked(cell):
            return false
        if extra_blocked_cells.has(cell):
            return false
        if cell == player_cell_after:
            return false
    return true
```

The primary `_can_apply_primary` keeps the existing axis, movement mode and
distance checks. A void primary is validated by the occupancy's void rules.

- [ ] **Step 7: Run the suite**

Run: `godot --headless --path . -s res://tests/run_runtime_suite.gd`
Expected: exit code 0 and the new A+ tests pass.

- [ ] **Step 8: Commit**

```bash
git add scripts/puzzle/core/puzzle_turn.gd scripts/puzzle/core/board_occupancy.gd scripts/puzzle/rules/puzzle_rule_set.gd scripts/puzzle/rules/sliding_puzzle_rule_set.gd tests/puzzle/test_void_slider_rules.gd tests/runtime_suite.gd
git commit -m "feat: resolve void slider push turns"
```

---

### Task 3: Snapshot history, compound turns and undoable reset

**Files:**
- Modify: `scripts/puzzle/systems/puzzle_session.gd`
- Test: `tests/puzzle/test_sliding_puzzle_core.gd`
- Test: `tests/puzzle/test_puzzle_history.gd`

- [ ] **Step 1: Add failing history tests**

In `test_sliding_puzzle_core.gd` add:

```gdscript
func _assert_reset_is_undoable(failures: Array[String]) -> void:
    var session := PuzzleSession.new(_make_goal_fixture())
    session.try_move(PuzzleMove.new(0, Vector2i(0, 0), Vector2i(1, 0)))
    if not session.reset():
        failures.append("reset() did not report an operation")
    if session.get_move_count() != 0 or session.current_state.get_piece(0).cell != Vector2i.ZERO:
        failures.append("reset did not restore the initial board")
    if not session.undo():
        failures.append("reset was not undoable")
    if session.current_state.get_piece(0).cell != Vector2i(1, 0) or session.get_move_count() != 1:
        failures.append("undo after reset did not restore the pre-reset state")
```

In `test_puzzle_history.gd` test a compound turn: build a normal mover and a
void piece, call `session.try_move`, assert both cells changed, call `undo`,
assert both restored.

- [ ] **Step 2: Run and confirm failures**

Run: `godot --headless --path . -s res://tests/run_runtime_suite.gd`
Expected: failures for reset undo and compound turn.

- [ ] **Step 3: Rewrite `PuzzleSession` with snapshots**

```gdscript
class_name PuzzleSession
extends RefCounted

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
    rules = p_rules if p_rules != null else SlidingPuzzleRuleSet.new(p_definition)
    reset_initial()


func reset_initial() -> void:
    current_state = _build_initial_state()
    _undo_stack.clear()
    _redo_stack.clear()
    _move_count = 0
    last_turn = null
    last_action = &""


func try_move(move: PuzzleMove, extra_blocked_cells: Array[Vector2i] = [], player_cell_after: Vector2i = Vector2i(-1, -1)) -> bool:
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


func get_move_count() -> int:
    return _move_count


func _snapshot(kind: StringName) -> Dictionary:
    return {"state": current_state.duplicate_state(), "move_count": _move_count, "kind": kind}


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
```

Keep `is_solved`, `get_legal_moves`, `set_rider`, `clear_rider`. Replace the old
`reset()` call in `_init` with `reset_initial()` so initialization does not push
history.

- [ ] **Step 4: Run the suite**

Run: `godot --headless --path . -s res://tests/run_runtime_suite.gd`
Expected: exit code 0; old session tests and new reset/compound tests pass.

- [ ] **Step 5: Commit**

```bash
git add scripts/puzzle/systems/puzzle_session.gd tests/puzzle/test_sliding_puzzle_core.gd tests/puzzle/test_puzzle_history.gd
git commit -m "feat: make puzzle moves and reset undoable"
```

---

### Task 4: Board turn sync, void selection and exit guard

**Files:**
- Modify: `scripts/puzzle/view/puzzle_board.gd`
- Test: `tests/puzzle/test_puzzle_void_zone.gd` (or `test_puzzle_history.gd`)

- [ ] **Step 1: Add failing board tests**

In `test_puzzle_history.gd`, after building a board with a void piece:

```gdscript
if board.call("get_piece_at_cell", void_cell) != void_piece:
    failures.append("board did not prioritize the void piece for selection")
if board.call("_player_rides", void_piece):
    failures.append("player was allowed to ride a void piece")
```

Test that `_player_cell_inside_void` detects a void piece and that
`_exit_drag_mode` refuses while the player is inside it.

- [ ] **Step 2: Run and confirm failures**

Run: `godot --headless --path . -s res://tests/run_runtime_suite.gd`
Expected: failures for void selection/guard.

- [ ] **Step 3: Board changes**

Add:

```gdscript
@export var undo_action: StringName = &"undo"
@export var reset_action: StringName = &"reset"
@export var blocked_cells: Array[Vector2i] = []

var _piece_tweens: Dictionary = {}
```

In `_build_session_from_scene_pieces`, copy:

```gdscript
piece_def.is_void = piece_node.is_void
definition.board.blocked_cells = blocked_cells.duplicate()
```

Make `_player_rides` return false for void pieces:

```gdscript
if piece.is_void:
    return false
```

Make `_select_piece` skip attach/register for void pieces:

```gdscript
if piece.is_void:
    return
```

Prioritize void in `get_piece_at_cell`:

```gdscript
var void_pick: PuzzlePiece = null
var one_way_pick: PuzzlePiece = null
var fallback: PuzzlePiece = null
for piece in _pieces:
    var offset := cell - piece.get_logical_cell()
    if piece.is_void:
        void_pick = piece
    elif piece.one_way_shape.has(offset):
        one_way_pick = piece
    elif fallback == null and piece.shape.has(offset):
        fallback = piece
if void_pick != null: return void_pick
if one_way_pick != null: return one_way_pick
return fallback
```

Add void footprint checks:

```gdscript
func _player_cell_inside_void() -> bool:
    if _player == null or not is_instance_valid(_player):
        return false
    var cell := player_cell_from_world()
    if _void_zone != null and _void_zone.has_world_position(
        _player.global_position + Vector2(-4.0, -8.0)
    ):
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
```

Exit guard:

```gdscript
if not force and (_player_cell_inside_void() or _player_cell_inside_piece()):
    return
```

- [ ] **Step 4: Replace single-piece animation with state sync**

Add tween management:

```gdscript
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


func _animate_piece_to(piece: PuzzlePiece, cell: Vector2i) -> void:
    if session == null:
        return
    _sync_pieces_from_state(true)
```

In `_move_piece_to`, compute the player's post-move cell and use the turn:

```gdscript
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

if session != null and session.try_move(move, extra_blocked, player_after):
    if riding:
        _attach_player_to(piece)
    _sync_pieces_from_state(true)
    _hide_preview()
else:
    _flash_invalid(piece, target)
```

- [ ] **Step 5: Run the suite**

Run: `godot --headless --path . -s res://tests/run_runtime_suite.gd`
Expected: exit code 0.

- [ ] **Step 6: Commit**

```bash
git add scripts/puzzle/view/puzzle_board.gd tests/puzzle/test_puzzle_history.gd tests/puzzle/test_puzzle_void_zone.gd
git commit -m "feat: sync compound void turns on the puzzle board"
```

---

### Task 5: Z undo and R reset scoped to boards containing the player

**Files:**
- Modify: `project.godot`
- Modify: `scripts/puzzle/view/puzzle_board.gd`
- Test: `tests/puzzle/test_puzzle_history.gd`

- [ ] **Step 1: Add failing board history/scope tests**

In `test_puzzle_history.gd`:

```gdscript
# player outside the board: no board action
board.call("set_player_to_cell", Vector2i(99, 99))
if board.call("_is_player_inside_board_rect"):
    failures.append("player outside the board was considered active")

# player inside: undo/reset work
board.call("set_player_to_cell", Vector2i(1, 1))
board.call("_reset_puzzle")
if board.get("session").current_state.get_piece(0).cell != initial_cell:
    failures.append("R did not reset the board")
board.call("_undo")
if board.get("session").current_state.get_piece(0).cell != moved_cell:
    failures.append("Z did not undo the reset")
```

- [ ] **Step 2: Run and confirm failures**

Run: `godot --headless --path . -s res://tests/run_runtime_suite.gd`
Expected: failures for missing input actions/board methods.

- [ ] **Step 3: Add input actions**

Add to the `[input]` section of `project.godot`:

```text
undo={
"deadzone": 0.2,
"events": [Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":-1,"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"pressed":false,"keycode":90,"physical_keycode":90,"key_label":0,"unicode":122,"location":0,"echo":false,"script":null)
]
}
reset={
"deadzone": 0.2,
"events": [Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":-1,"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"pressed":false,"keycode":82,"physical_keycode":82,"key_label":0,"unicode":114,"location":0,"echo":false,"script":null)
]
}
```

- [ ] **Step 4: Add board input and methods**

```gdscript
func _is_player_inside_board_rect() -> bool:
    if _player == null or not is_instance_valid(_player):
        return false
    return Rect2i(Vector2i.ZERO, board_size).has_point(player_cell_from_world())


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
```

At the start of `_process`, after `session == null` check and player resolution:

```gdscript
    if mode == ControlMode.DRAG and _is_player_inside_board_rect():
        if Input.is_action_just_pressed(String(undo_action)):
            _undo()
            return
        if Input.is_action_just_pressed(String(reset_action)):
            _reset_puzzle()
            return
```

- [ ] **Step 5: Run the suite**

Run: `godot --headless --path . -s res://tests/run_runtime_suite.gd`
Expected: exit code 0.

- [ ] **Step 6: Commit**

```bash
git add project.godot scripts/puzzle/view/puzzle_board.gd tests/puzzle/test_puzzle_history.gd
git commit -m "feat: add slider-mode undo and reset"
```

---

### Task 6: Author the bottom-left void piece in `room_start_00`

**Files:**
- Modify: `scenes/levels/main/room_start_00.tscn`
- Test: `tests/puzzle/test_puzzle_room_contract.gd` or new `test_start_room_void.gd`

- [ ] **Step 1: Add a failing source-room contract test**

Create `tests/puzzle/test_start_room_void.gd`:

```gdscript
extends Node
const SOURCE := "res://scenes/levels/main/room_start_00.tscn"

func run() -> Array[String]:
    var failures: Array[String] = []
    var root: Node = (load(SOURCE) as PackedScene).instantiate()
    add_child(root)
    var board := root.get_node("RoomContent/Entities/PuzzleBoard")
    var void_piece: PuzzleTilePiece = null
    for piece in board.get_children():
        if piece is PuzzleTilePiece and piece.is_void:
            void_piece = piece
            break
    if void_piece == null:
        failures.append("room_start_00 has no void slider")
    else:
        if void_piece.get_logical_cell() != Vector2i(0, 14):
            failures.append("void slider is not the bottom-left 13x7 chunk")
        if void_piece.shape.size() != 91:
            failures.append("void slider footprint is not 13x7")
        if void_piece.x_move_distance != 13 or void_piece.y_move_distance != 7:
            failures.append("void slider distances are not 13/7")
        if void_piece.get_node_or_null("VoidTiles") == null:
            failures.append("void slider has no VoidTiles layer")
    if root.get_node_or_null("RoomContent/Entities/PuzzleBoard/VoidZone") != null:
        failures.append("room_start_00 still has the static VoidZone placeholder")
    root.free()
    return failures
```

Register it in `tests/runtime_suite.gd`.

- [ ] **Step 2: Run and confirm failure**

Run: `godot --headless --path . -s res://tests/run_runtime_suite.gd`
Expected: failure for missing void slider.

- [ ] **Step 3: Generate the 13x7 void tile data**

Use a temporary Godot script or the tilemap editor to produce a `TileMapLayer`
with cells `(0..12, 0..6)` using atlas `(0, 5)`. Save the base64
`tile_map_data` string.

- [ ] **Step 4: Edit `room_start_00.tscn`**

Remove the empty static `VoidZone` node added earlier.

Append under `RoomContent/Entities/PuzzleBoard`:

```text
[node name="PuzzleVoidPiece" type="Polygon2D" parent="RoomContent/Entities/PuzzleBoard" index="9"]
position = Vector2(0, 112)
script = ExtResource("3_hgfgl")
x_move_distance = 13
y_move_distance = 7
metadata/_custom_type_script = "uid://b8b1cilmjmmes"

[node name="VoidTiles" type="TileMapLayer" parent="RoomContent/Entities/PuzzleBoard/PuzzleVoidPiece" index="0"]
z_index = 5
modulate = Color(1, 1, 1, 0.22)
tile_map_data = PackedByteArray("<generated>")
tile_set = ExtResource("4_neljd")
collision_enabled = false
```

The board already has pieces at indices 0..7; the new node is index 8 or 9
depending on the existing child count. Use the actual next index.

- [ ] **Step 5: Run the suite**

Run: `godot --headless --path . -s res://tests/run_runtime_suite.gd`
Expected: exit code 0.

- [ ] **Step 6: Commit (do not commit user-owned generated/world files)**

```bash
git add scenes/levels/main/room_start_00.tscn tests/puzzle/test_start_room_void.gd tests/runtime_suite.gd
git commit -m "feat: add the room_start_00 void slider"
```

If `room_start_00.tscn` is still intentionally uncommitted user work, skip this
commit and report it as a working-tree change instead.

---

### Task 7: Documentation and final verification

**Files:**
- Modify: `docs/extension-guide.md`
- Modify: `游戏机制设计.md`
- Maybe `docs/project-structure.md`

- [ ] **Step 1: Document the rules**

Add the A+ rule, void piece authoring, Z/R behavior, reset scope and multi-board
behavior to `游戏机制设计.md` and `docs/extension-guide.md`.

- [ ] **Step 2: Run the full suite twice**

```bash
godot --headless --path . -s res://tests/run_runtime_suite.gd
godot --headless --path . -s res://tests/run_runtime_suite.gd
```

Expected: exit code 0 both times.

- [ ] **Step 3: Smoke the main scene**

```bash
godot --headless --path . --quit-after 30
```

Expected: no parse/runtime errors.

- [ ] **Step 4: Commit docs**

```bash
git add docs/extension-guide.md 游戏机制设计.md docs/superpowers/specs/2026-10-24-void-slider-undo-reset-design.md docs/superpowers/plans/2026-10-24-void-slider-undo-reset.md
git commit -m "docs: document void sliders and puzzle undo/reset"
```

---

## Self-Review

- **Spec coverage:** A+ trigger/validation → Task 2; void piece/body → Task 1;
  compound move and reset history → Task 3; board sync/selection/guard → Task 4;
  Z/R scope → Task 5; room_start void → Task 6; docs → Task 7.
- **No placeholders:** The only generated value is the 13x7 `tile_map_data`
  string, produced from the TileMapLayer API in Task 6; all gameplay code and
  commands are explicit.
- **Type consistency:** `PuzzleTurn.moves`, `PieceDefinition.is_void`,
  `PuzzleTilePiece.is_void`, `PuzzleSession.last_turn`, and
  `resolve_turn(..., player_cell_after)` are used consistently across tasks.
