# Void Slider and Puzzle Undo/Reset Design

Date: 2026-10-24
Project: wellwell / newcore01 puzzle branch
Status: Implemented 2026-10-24 (A+); verified by the headless runtime suite

## Goal

Add a movable **void slider** to the tile-based sliding-block system. The void
slider is a normal puzzle piece whose footprint is void: other pieces may pass
through it, while the player cannot enter it in jump mode. When another piece
fully covers the void slider's minimum rectangle, the void slider is pushed in
the opposite direction by the covering piece's displacement.

Also add slider-mode undo/reset:

- `Z`: undo one operation.
- `R`: reset the puzzle board.
- Reset is itself undoable, so `Z` after `R` restores the pre-reset state.
- Input applies only to boards whose rectangle contains the player.

## Non-Goals

- No room/level checkpoint changes; reset is board-local.
- No solver/AI integration.
- No new tile artwork; the existing primordial tileset is used.
- No changes to save-game format.

## Core Concepts

- **Piece**: a logical slider with a shape, anchor cell, movement mode and
  axis-specific move distances.
- **Minimum rectangle (min rect)**: the smallest axis-aligned cell rectangle
  containing a piece's actual footprint. This is used for push detection.
- **Void piece**: a slider whose cells are void. It is not a wall and not a
  one-way platform. Other pieces may overlap it; the player is blocked by it in
  jump mode.
- **Normal piece**: any non-void piece, including hollow pieces whose min rect
  contains unoccupied cells.

## Auto-Push Rule (A+)

A primary move is the piece the player selected. It may be a normal piece or a
void piece.

For each normal primary move:

1. Validate the primary move with the existing occupancy rules, except that
   other void pieces' cells are passable.
2. Compute the primary mover's min rect at its target cell.
3. For every void piece V whose min rect at its current cell is fully enclosed
   by the mover's target min rect:
   - Compute `V_target = V.cell - (primary.to_cell - primary.from_cell)`.
   - V keeps its own shape and moves by that full opposite displacement.
   - Validate V_target:
     - all V footprint cells are inside the board;
     - no V footprint cell is in `BoardDefinition.blocked_cells` (static
       walls);
     - no V footprint cell equals the player's post-move cell;
     - other normal pieces and other void pieces do NOT block V; V may overlap
       them.
4. If any triggered V is invalid, the entire primary move is rejected. The
   primary piece and all V pieces stay put.
5. If all triggered V's are valid, apply the primary move and all V moves as one
   atomic turn.
6. One primary move triggers at most one V move per V. There is no chain: if a
   large mover still covers V after V moves, V does not move again until the
   mover moves again.
7. Partial overlap of min rects does not trigger V. A mover may overlap V cells
   without pushing it.

A void primary move does not trigger any other piece. V may overlap normal and
void pieces when moving itself. V cannot move outside the board, onto a static
wall cell, or onto the player's current cell.

### Why A+

- A hollow mover's **min rect** can cover V even though its actual cells cannot.
  This keeps hollow pieces able to push the void and block player routes.
- Because the void's destination is validated atomically, a void can never be
  pushed into a wall. The earlier bbox-only counterexample is rejected as a
  whole turn.

## Player Interaction

- The player cannot enter a void piece's footprint in jump mode.
- While control is locked for slider riding, the player's void collision bit is
  removed, so a rider may follow a normal piece through void.
- The player cannot ride a void piece. Selecting V only moves V; it never
  attaches the player.
- A void piece is always drawn above normal pieces (above their solid/one-way
  layers) but below the player and mode overlays. Void visuals must be
  translucent so the covered piece remains visible.
- Selection hit-testing prioritizes void pieces over one-way and wall pieces.
- Exiting slider mode is refused while the player's cell is inside any piece
  footprint or void cell. This prevents embedding after a reset or undo.

## Undo / Reset

- Inputs are consumed only when the board is in `DRAG` mode and the player's
  cell is inside `Rect2i(0, 0, board_size)`.
- Multiple boards containing the player all react to the same input. A board
  not containing the player ignores it.
- `Z` is `undo`; `R` is `reset`. `Z` is checked before `R` in the same frame.
- A **move operation** includes the primary move and every induced void move;
  one undo restores all of them.
- A **reset operation** restores every piece (including void pieces) to its
  authored initial cell and sets move count to 0.
- Reset is pushed onto the undo history. `Z` after `R` restores the pre-reset
  board state and move count.
- `R` on an already initial board is a no-op.
- `Z` with no history is a no-op.
- Reset clears the redo stack. Redo remains available through the session API.
- Reset does not move the player. If reset/undo places a piece or void on the
  player's cell, slider mode remains active and the exit guard blocks leaving
  until the piece is moved or the operation is undone.
- Undo/redo/reset animate changed pieces with the existing short tween. Existing
  piece tweens are killed before a new sync.

## Data Model

### PieceDefinition / PuzzlePiece

Add:

```gdscript
@export var is_void: bool = false
```

For a void piece, `shape` is the void footprint, `wall_shape` and
`one_way_shape` are empty. `get_bounds()` remains the min rect.

### Void tile piece

`PuzzleTilePiece` gains:

- `const VOID_LAYER_NAME := "VoidTiles"`
- `var is_void: bool`
- `var _void_layer: TileMapLayer`

A `VoidTiles` child layer defines the void footprint. It is a visual layer with
`collision_enabled = false`; the script builds a player-only `StaticBody2D` on
physics layer 4 (`void`, bit 8) from the painted cells. The body moves with the
piece and is named `VoidBody`.

`VoidTiles` is exclusive with `SolidTiles`/`OneWayTiles`. If a piece contains
void cells, it is a void slider; a configuration warning is emitted if wall or
one-way layers are also present. In that invalid hybrid case `VoidTiles` wins:
the wall/one-way layers are ignored for footprint and their runtime collision is
disabled, so a void slider can never become a hidden wall.

The tile mode flag must include the void layer so a void-only piece does not
fall back to the legacy Polygon2D behavior.

### Void body

`PuzzleTilePiece` builds one `StaticBody2D`:

```text
collision_layer = 8
collision_mask = 0
one RectangleShape2D per void cell
```

The player scene uses `collision_mask = 9` (world + void). `PlayerController`
removes/restores bit 8 when `set_control_locked()` is called.

### PuzzleTurn

New `scripts/puzzle/core/puzzle_turn.gd`:

```gdscript
class_name PuzzleTurn
extends RefCounted

var moves: Array[PuzzleMove] = []

func add(piece_index: int, from_cell: Vector2i, to_cell: Vector2i) -> void
func is_empty() -> bool
```

The first move is the primary move; remaining moves are induced void moves.

### BoardOccupancy

- A void piece contributes no wall or one-way cells to other pieces.
- A void mover ignores other normal and void pieces; it still checks board
  bounds, blocked cells and extra blocked/player cells.
- A normal mover ignores other void pieces' cells but keeps existing wall,
  one-way and rider rules.

### SlidingPuzzleRuleSet

- `resolve_turn(state, move, extra_blocked_cells, player_cell_after)` returns a
  `PuzzleTurn` or `null`.
- The min-rect test uses `Rect2i.encloses`.
- V target validation uses the void footprint, `blocked_cells`, board bounds,
  extra blocked cells and `player_cell_after`.
- `can_apply_move()` becomes "resolve_turn is non-empty".
- `get_legal_moves()` keeps its existing signature and resolves induced moves
  with the default player cell (pure rules/tests only).

### PuzzleSession

Replace single-move history with snapshot history:

- `_undo_stack` / `_redo_stack` of dictionaries containing a duplicated
  `BoardState`, move count and operation kind.
- `try_move()` resolves a turn, pushes a snapshot, applies every move, increments
  move count by 1.
- `reset()` pushes a snapshot, restores initial state, move count 0; no-op on an
  already initial board.
- `undo()`/`redo()` restore snapshots.
- `get_move_count()` returns the snapshot move count.
- `last_turn` exposes the applied turn for view animation.

### PuzzleBoard

- `@export var undo_action: StringName = &"undo"`
- `@export var reset_action: StringName = &"reset"`
- `@export var blocked_cells: Array[Vector2i] = []` copied into the board
  definition.
- `_piece_tweens` keyed by piece index; kill before syncing.
- `_sync_pieces_from_state(animate)` updates all piece cells/positions from the
  session.
- `_undo()` and `_reset_puzzle()` call the session, sync pieces, clear target
  preview; reset clears selection and attachment.
- `_is_player_inside_board_rect()` checks the player's board cell.
- `_process()` checks undo then reset only in `DRAG` and inside the board rect.
- `_player_cell_inside_void()` checks the static void zone plus every void
  piece's current footprint.
- `_player_cell_inside_piece()` checks every piece footprint for the exit guard.

### Input Map

Add:

- `undo`: Z (keycode 90)
- `reset`: R (keycode 82)

Z remains bound to jump. Jump is ignored while the player is control-locked, so
slider-mode Z is unambiguous.

## Room Start 00

The authored `scenes/levels/main/room_start_00.tscn` gets a ninth bottom-left
void slider:

- class: `PuzzleTilePiece`
- position: `(0, 14 * 8) = (0, 112)`
- `x_move_distance = 13`, `y_move_distance = 7`
- child `VoidTiles` layer: 13x7 cells, primordial tileset, collision disabled,
  z_index 5, translucent modulate
- no `SolidTiles`/`OneWayTiles`
- the empty static `VoidZone` node added earlier is removed

The existing eight pieces remain unchanged. Their X/Y distances are already 13/7.

## Testing

Pure tests:

- hollow mover's min rect covers V → turn contains primary + V move;
- partial overlap → no V move;
- V target blocked by `blocked_cells` → whole turn invalid;
- V target inside board/player → invalid;
- V target overlapping another piece → valid;
- large mover still covering V after V moves → exactly one V move;
- multiple V's, one blocked → invalid;
- void mover ignores normal pieces but is blocked by wall/player;
- exact opposite displacement and axis distance.

Tile-piece tests:

- `VoidTiles` piece is void, shape is void cells, no wall/one-way;
- generated `VoidBody` is layer 8 with one shape per cell;
- board copies `is_void`;
- `get_piece_at_cell` prioritizes V;
- player cannot ride V.

Session/board tests:

- reset is undoable and restores move count;
- undo after reset then undo again reaches the previous move;
- compound move undo restores primary + V;
- Z/R scope: player inside board rect vs outside;
- overlapping boards all undo/reset;
- reset clears selection and the exit guard blocks while the player is inside a
  piece/void.

Room contract:

- room_start_00 source loads with 9 pieces;
- void piece at cell `(0, 14)`, shape 91, `is_void`, x/y 13/7;
- no static `VoidZone` node;
- spawn cell is not void.

## Edge Cases and Decisions

- A void pushed into a wall/blocked cell invalidates the primary move; no partial
  push and no void-in-wall state.
- A large mover that still covers V after the push does not chain; the next move
  of the mover can push again.
- Void pieces may overlap normal pieces, each other and other void pieces.
- The player is a wall for V's destination; a rider's post-move cell is used when
  the player is riding the primary mover.
- Reset is board-local and does not move the player; the exit guard and undo
  provide recovery if the player ends up inside a piece/void.
- Multiple boards containing the player all act on Z/R; each board has its own
  history and reset scope.


## Implementation Notes

Implemented files:

- `scripts/puzzle/core/puzzle_turn.gd`
- `scripts/puzzle/definition/piece_definition.gd`
- `scripts/puzzle/view/puzzle_piece.gd`
- `scripts/puzzle/view/puzzle_tile_piece.gd`
- `scripts/puzzle/core/board_occupancy.gd`
- `scripts/puzzle/rules/puzzle_rule_set.gd`
- `scripts/puzzle/rules/sliding_puzzle_rule_set.gd`
- `scripts/puzzle/systems/puzzle_session.gd`
- `scripts/puzzle/view/puzzle_board.gd`
- `project.godot`
- `scenes/levels/main/room_start_00.tscn`

Tests:

- `tests/puzzle/test_void_slider.gd`: A+ push, partial overlap, atomic rejection,
  player-cell blocking, V-primary rules, no chaining, compound undo/redo, and
  undoable reset.
- `tests/puzzle/test_puzzle_history.gd`: Z/R scoping, multiple overlapping
  boards, undo priority, input bindings, and board-level reset/undo.
- `tests/puzzle/test_start_room_void.gd`: room_start_00 source contract.
- `tests/puzzle/test_puzzle_tile_piece.gd`: VoidTiles footprint, VoidBody,
  hybrid-layer behavior, and void hit-test priority.

Deviations from the draft:

- The static `PuzzleVoidZone` remains for compatibility and legacy static
  regions; `room_start_00` no longer uses it.
- The ninth `room_start_00` piece is named `PuzzleTilePiece9`, uses `z_index = 5`,
  and reuses the existing 13x7 void tile data.
- `PuzzleBoard` centralizes Z/R scoping in `_handle_history_input()` so the
  priority and multi-board rules are testable without polling `Input`.
- The runtime suite command is
  `godot --headless --path . -s res://tests/run_runtime_suite.gd`.
