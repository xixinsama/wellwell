# Gamepad Right-Stick Aim Selection Design

Date: 2026-10-24
Project: wellwell / newcore01 puzzle branch
Status: Implemented 2026-10-24; pending manual controller acceptance

## Goal

Add right-stick directional selection to slider mode. While the player holds a
direction, show an aim arrow from the currently selected slider's center to the
nearest selectable slider in that direction. Releasing the stick to its center
switches the selection to that slider.

This extends the existing gamepad slider controls without changing the
left-stick/D-pad movement, LB/RB cycling, A/B shortcuts, or history controls.

## Confirmed Interaction

1. A slider is selected and slider mode is active.
2. The player deflects the right stick beyond the aim deadzone.
3. The board chooses the nearest eligible slider whose center lies inside a
   45-degree cone around the stick direction.
4. An arrow is drawn from the selected slider's center to that target's center.
5. Moving the stick updates the target and arrow continuously.
6. Releasing the stick (aim vector below the deadzone) switches selection to the
   most recently displayed target, then hides the arrow.
7. If no target was displayed, release only hides the arrow and leaves the
   selection unchanged.

The arrow is a preview, not a move command. It never moves a piece, creates
history, or changes the puzzle step count.

## Target Eligibility

The existing gamepad eligibility rules are reused:

- `PuzzlePiece.enable` must be true.
- `movement_mode` must not be `STATIC`.
- The selected piece itself is excluded.
- Disabled void sliders are excluded but remain passively pushable.
- Enabled void sliders are eligible.

Candidates are considered in scene order as the deterministic tie-breaker when
two centers have the same distance.

## Geometry

- **Piece center:** center of the piece's minimum bounding rectangle, in board
  local coordinates.
- **Aim vector:** screen-oriented right-stick vector from `Input.get_vector()`;
  right is `+x`, up is `-y`.
- **Direction test:** a candidate is eligible when the dot product between the
  normalized aim vector and the normalized center-to-center vector is at least
  `cos(45 degrees)` (approximately `0.7071068`).
- **Distance:** squared Euclidean center-to-center distance. The nearest eligible
  candidate in the 45-degree cone wins.
- **Deadzone:** the board rejects aim vectors shorter than `0.3`. The InputMap
  actions use a `0.2` per-axis deadzone.

If the selected piece and another piece have identical centers, the candidate
is skipped to avoid a zero-length arrow.

## Visual

Add a runtime-only `PuzzleAimArrow` Node2D child to each board:

- `z_index = 20` (same layer as the target preview; the aim arrow is added after
  the preview so it draws on top).
- Hidden by default.
- Draws a one-pixel warm-yellow line from selected center to target center and
  a small filled triangular arrowhead at the target.
- Hidden when there is no target, no selection, stick release, cancel, mode
  exit, reset, or selection change.

## Input

Add four project actions, all gamepad-only, to support right-stick aiming and
Input Mapping remapping:

| Action | Right-stick axis |
| --- | --- |
| `aim_left` | axis 2, value -1 |
| `aim_right` | axis 2, value +1 |
| `aim_up` | axis 3, value -1 |
| `aim_down` | axis 3, value +1 |

`PuzzleBoard` reads the vector with:

```gdscript
Input.get_vector(aim_left_action, aim_right_action, aim_up_action, aim_down_action)
```

Add labels for the four actions to `localization/menu.csv`.

## Lifecycle and Input Order

`_process()` order becomes:

1. undo/reset;
2. mode switch;
3. button-based slider selection;
4. aim update/release;
5. mouse selection;
6. direction movement.

The aim update is called only while slider mode is active. It is skipped and
cleared when the board is not selection-active or no piece is selected.

Changing selection (A/B, LB/RB, mouse, reset, or a successful stick release)
clears the old arrow. If the stick remains deflected after a selection change,
the next frame recomputes a target for the new selected piece.

If slider mode exits while a target is shown, the arrow is cleared and the
pending release switch is discarded.

## Board API

Add:

```gdscript
@export var aim_left_action: StringName = &"aim_left"
@export var aim_right_action: StringName = &"aim_right"
@export var aim_up_action: StringName = &"aim_up"
@export var aim_down_action: StringName = &"aim_down"

func _read_stick_aim() -> Vector2
func _handle_stick_selection(aim: Vector2) -> void
func _release_stick_selection() -> void
func _clear_stick_aim() -> void
func _find_directional_target(selected: PuzzlePiece, aim: Vector2) -> PuzzlePiece
func _piece_center(piece: PuzzlePiece) -> Vector2
```

The explicit `aim` parameter makes headless tests independent of physical
controller state.

## Edge Cases

- Aim vector under deadzone with no target: no switch.
- Aim vector under deadzone after a target: switch to the target.
- No eligible candidate in the cone: arrow hidden; release leaves selection.
- Player not selection-active or no selected piece: no arrow, no switch.
- Disabled/static pieces never become targets.
- Disabled void pieces never become targets.
- Aiming while a piece is moving/tweening uses current visual centers and
  updates the arrow each frame.
- Cancel/mode exit clears the pending target so release cannot switch later.
- A stick release and a button selection in the same frame use the documented
  process order; button selection runs first, then the aim update.

## Testing

Add `tests/puzzle/test_gamepad_stick_aim.gd` and register it in
`tests/runtime_suite.gd`.

Coverage:

- all four `aim_*` actions exist with the correct right-stick axes and signs;
- right aim selects the nearest eligible piece and skips a nearer disabled one;
- arrow visibility and center-to-center endpoints;
- release switches selection and hides the arrow;
- no-target aim hides the arrow and release keeps selection;
- disabled/static pieces are skipped;
- cancel and mode exit discard the pending target;
- selection/aim does not create history entries;
- live source wiring reads the four actions and calls the stick handler.

Manual acceptance:

- enter slider mode and aim with the right stick;
- confirm the arrow points to the nearest slider in each direction;
- move the stick between directions and see the target update;
- release to switch selection;
- confirm disabled sliders are skipped;
- verify LB/RB, A/B, movement, undo/reset, and mouse/keyboard still work.

## Acceptance Criteria

- The arrow appears only while the right stick is deflected and a target exists.
- Release switches to the most recently displayed target exactly once.
- No target, cancel, mode exit, or reset never causes an unintended switch.
- Existing gamepad, mouse, keyboard, puzzle, void, and history behavior remains
  unchanged.
