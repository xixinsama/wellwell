# Gamepad Slider Controls Design

Date: 2026-10-24
Project: wellwell / newcore01 puzzle branch
Status: Approved by user; implementation pending

## Goal

Add first-class gamepad support for the sliding-puzzle mode. The controller must
be able to enter slider mode, choose any controllable piece, slide it, return to
the ridden piece, cancel selection, undo, reset, and leave slider mode without
using the mouse or keyboard.

The existing keyboard and mouse controls remain available and unchanged.
Existing jump-mode gamepad controls remain unchanged.

## Non-Goals

- No virtual cursor or free mouse-pointer emulation.
- No analog drag gesture; every slide remains one discrete action per press.
- No held-button auto-repeat.
- No new gamepad-driven menu navigation.
- No changes to the puzzle rules, void-push rules, history semantics, or
  `enable` semantics.
- No vibration, button-prompt HUD, or controller-detection UI.
- No changes to the input-mapping addon implementation.

## Confirmed Control Scheme

Slider mode is entered with the existing `switch_mode` action (`Tab` / `Y`).

| Action | Keyboard default | Gamepad default | Slider-mode behavior |
| --- | --- | --- | --- |
| `slider_prev` | unbound | LB (`JOY_BUTTON_LEFT_SHOULDER`) | Select previous controllable piece |
| `slider_next` | unbound | RB (`JOY_BUTTON_RIGHT_SHOULDER`) | Select next controllable piece |
| `slider_select_rider` | unbound | A (`JOY_BUTTON_A`) | Re-select the piece the player is riding |
| `slider_cancel` | unbound | B (`JOY_BUTTON_B`) | Clear the current selection |
| `undo` | `Z` (kept) | Back / View (`JOY_BUTTON_BACK`) | Undo one operation |
| `reset` | `R` (kept) | Start / Menu (`JOY_BUTTON_START`) | Reset the board immediately |
| `switch_mode` | `Tab` (kept) | Y (`JOY_BUTTON_Y`) | Enter or leave slider mode |
| `move_left/right/up/down` | WASD / arrows (kept) | D-pad / left stick (kept) | Move the selected piece |

`slider_select_rider` is a separate action even though it shares the A button
with `jump`; `slider_cancel` is separate even though it shares B with `dash`.
Inside slider mode the player is control-locked, so the jump/dash intents cannot
fire. Outside slider mode the board ignores the slider actions.

New actions intentionally have no keyboard defaults so they cannot collide with
existing gameplay keys. Players may assign keyboard bindings through the
existing Input Mapping settings if desired.

## Selection Model

### Controllable pieces

A piece is eligible for gamepad selection when all of the following hold:

- it is a child of the board and therefore present in scene order;
- `PuzzlePiece.enable` is true;
- its definition `movement_mode` is not `STATIC`.

The eligible order is exactly the board's child order, which is also the
definition index order. Disabled pieces and static pieces are skipped. An
enabled void piece is eligible; a disabled void piece is not.

### Board selection scope

Controller selection is scoped to a board that is active for the player. A board
is selection-active when either condition holds:

1. the player's 8x8 top-left cell lies inside `Rect2i(0, 0, board_size)`; or
2. the player rides any non-void piece of that board (using the existing
   `_player_rides()` rule; the piece may itself be disabled).

This avoids one `LB`/`RB` press cycling the selection in every board in a room
with multiple puzzles. Boards that are not selection-active ignore the four new
slider-selection actions and do not auto-select a piece.

The existing history scope for `undo`/`reset` is unchanged: it still uses the
board rectangle, not the riding exception.

### Entering slider mode

On entering slider mode, synchronously select:

1. the first controllable piece in scene order that the player rides; otherwise
2. the first controllable piece in scene order; otherwise
3. no piece.

Only selection-active boards auto-select. If the mode is entered by clicking a
piece, this initial selection happens first and the clicked piece then replaces
it through the existing mouse path.

Entering slider mode must not move the player or produce a history entry.

### Cycling

`RB` selects the next eligible piece and `LB` selects the previous eligible
piece.

- The search starts after the currently selected piece.
- Order wraps at both ends.
- If there is no current selection, `RB` selects the first eligible piece and
  `LB` selects the last eligible piece.
- If the current selection is not in the eligible list (for example it became
  disabled at author time and the board was rebuilt), `RB` selects the first
  eligible piece and `LB` selects the last eligible piece.
- With zero eligible pieces the action is a no-op.
- With one eligible piece the action leaves that piece selected.

Selection itself is immediate; there is no separate confirm step. Changing the
selection reuses the existing `_select_piece()` behavior, including attaching the
player to the new piece when the player rides it and detaching from the old one.

### A: select ridden piece

`A` searches eligible pieces in scene order and selects the first piece for which
`_player_rides()` is true. Void pieces fail `_player_rides()` and are therefore
never selected by this shortcut. If the player is not riding anything, `A` is a
no-op.

### B: clear selection

`B` calls the existing `_deselect_piece()` path. If there is no selection, the
action is a no-op. Existing exit/void protection inside `_deselect_piece()` still
applies.

### Reset

`R` / Start keeps the existing immediate reset behavior. After a reset attempt
in slider mode, the board runs the normal entry-time selection rule again. This
also applies when the board is already at its initial state and `session.reset()`
returns false, so a controller user never loses selection merely by pressing
reset at the start.

Selection after reset must not move the player and must not create history.

### Leaving slider mode

Existing mode-exit behavior is unchanged. The board clears selection, detaches
the rider, unlocks the player, and applies the existing carried-rider air-jump
grant if applicable.

## Input Processing

`PuzzleBoard._process()` handles input in this order:

1. undo/reset input (`Z`/`R` or Back/Start);
2. mode switch (`Tab`/Y);
3. slider-selection input (`LB`/`RB`/A/B);
4. mouse selection and drag;
5. direction-key movement while in slider mode.

Selection is resolved before movement in the same frame, so a selection change
and a direction press in one frame operate on the newly selected piece.

Within the selection step, the deterministic priority is:

1. `slider_select_rider` (A);
2. `slider_next` (RB);
3. `slider_prev` (LB);
4. `slider_cancel` (B).

This priority is only relevant when multiple actions are injected on the same
frame. A single normal press behaves exactly as described above.

Direction movement remains one step per press and keeps the existing priority
left, right, up, down. There is no held-button repeat.

## Implementation Boundaries

### `scripts/puzzle/view/puzzle_board.gd`

Add exported action names with defaults:

```gdscript
@export var prev_piece_action: StringName = &"slider_prev"
@export var next_piece_action: StringName = &"slider_next"
@export var select_rider_action: StringName = &"slider_select_rider"
@export var cancel_selection_action: StringName = &"slider_cancel"
```

Add focused helpers:

```gdscript
func _is_selection_active() -> bool
func _controllable_pieces() -> Array[PuzzlePiece]
func _select_initial_piece() -> void
func _cycle_selection(direction: int) -> bool
func _select_rider_piece() -> bool
func _cancel_selection() -> bool
func _handle_selection_input(
    previous_pressed: bool,
    next_pressed: bool,
    select_pressed: bool,
    cancel_pressed: bool
) -> bool
```

`_handle_selection_input()` receives explicit booleans so headless tests do not
depend on Godot's `Input` singleton edge-press timing. `_process()` passes the
four `Input.is_action_just_pressed()` results into it.

`_enter_drag_mode()` calls `_select_initial_piece()` after locking the player.
`_reset_puzzle()` calls `_select_initial_piece()` when still in slider mode,
including the no-op reset path.

### `project.godot`

Add the four actions with `InputEventJoypadButton` defaults:

- `slider_prev`: button 9 (left shoulder)
- `slider_next`: button 10 (right shoulder)
- `slider_select_rider`: button 0 (A)
- `slider_cancel`: button 1 (B)

Append gamepad events to the existing actions:

- `undo`: button 4 (Back / View)
- `reset`: button 6 (Start / Menu)

Keep all existing keyboard and joypad events.

### `localization/menu.csv`

Add project action labels so the Input Mapping menu displays readable names in
English and Chinese:

```text
INPUT_ACTION_SWITCH_MODE
INPUT_ACTION_UNDO
INPUT_ACTION_RESET
INPUT_ACTION_SLIDER_PREV
INPUT_ACTION_SLIDER_NEXT
INPUT_ACTION_SLIDER_SELECT_RIDER
INPUT_ACTION_SLIDER_CANCEL
```

Reimport the translations after editing the CSV.

### Documentation

Update `游戏机制设计.md` with the confirmed gamepad table and selection rules.
Update `docs/extension-guide.md` with the new action names, selection scope, and
the explicit-boolean testing seam.

## Edge Cases

- No player: selection-active is false; all selection actions are no-ops.
- No eligible pieces: auto-selection clears; all four actions are no-ops.
- Player not inside any board and not riding a piece: no auto-selection and no
  gamepad selection actions on any board.
- Player rides a disabled piece: the board is selection-active, but the disabled
  piece is skipped; the first eligible piece is selected instead (or no piece if
  none are eligible).
- Player rides an enabled void piece: impossible by rule; `_player_rides()`
  returns false for void pieces.
- Player inside void while attached: existing `_select_piece()` and
  `_deselect_piece()` protections still apply.
- Disabled void: never selected or cycled, but continues to move passively when
  an enabled primary move fully covers it.
- Reset at the initial state: state and history remain unchanged, but selection
  is re-established for controller use.
- Mouse selection outside the player's active board: still works; the gamepad
  selection scope does not alter mouse behavior.
- Multiple overlapping boards: only selection-active boards auto-select or
  accept LB/RB/A/B. Existing per-board mouse selection and movement behavior is
  not otherwise changed.
- Keyboard/mouse-only players: unchanged controls and history shortcuts.

## Testing

Add `tests/puzzle/test_gamepad_selection.gd` and register it in
`tests/runtime_suite.gd`.

The test fixture builds a board with, in scene order:

1. an enabled piece;
2. a disabled piece (`enable = false`);
3. an enabled piece;
4. a static piece;
5. an enabled void piece;
6. a disabled void piece.

Cases to cover:

- entering slider mode selects the first eligible piece when the player is not
  riding anything;
- entering while riding an eligible piece selects that piece instead;
- entering while outside the board and not riding selects nothing;
- `RB` advances in scene order, skips disabled/static pieces, and wraps;
- `LB` moves backward, skips disabled/static pieces, and wraps;
- `A` selects the ridden piece and is a no-op without a rider;
- `B` clears the selection and is a no-op without one;
- reset re-establishes the entry selection;
- a disabled void piece is skipped by cycling but still moves passively in an
  A+ turn (covered by the existing void-slider suite, plus at least one
  selection assertion here);
- selection does not create history entries or move the player.

Input-contract assertions:

- `slider_prev`, `slider_next`, `slider_select_rider`, `slider_cancel` exist;
- their default joypad button indices are 9, 10, 0, and 1;
- `undo` retains `KEY_Z` and gains gamepad button 4;
- `reset` retains `KEY_R` and gains gamepad button 6;
- `switch_mode` retains its existing `Tab` and `Y` bindings.

Manual acceptance:

- Start `room_start_00.tscn` with a physical controller.
- Enter slider mode with Y; confirm the ridden or first eligible piece is
  outlined.
- Cycle with LB/RB, wrap, and verify disabled pieces are never selected.
- Move with D-pad and left stick; verify one cell/step distance per press.
- Move away from the ridden piece, press A, and verify the rider is selected.
- Press B and verify direction input no longer moves a piece.
- Slide a piece, press Back, and verify undo.
- Press Start and verify reset plus re-selection.
- Verify mouse and keyboard controls still work.
- Open Settings > Input Mapping and verify the four new actions are listed and
  their gamepad bindings can be replaced and reset.

## Acceptance Criteria

- A controller alone can enter slider mode, select every eligible piece, slide
  it, return to the ridden piece, cancel, undo, reset, and exit.
- Selection order is scene order; wrapping and disabled/static skipping are
  deterministic.
- Disabled void sliders remain passively pushable but are never selectable.
- Existing keyboard/mouse controls, history, void pushes, and rider air-jump
  behavior are unchanged.
- The complete headless runtime suite passes twice consecutively.
- `tools/validate_project.gd` passes.
