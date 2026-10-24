# Gamepad Slider Controls Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add controller selection, cycling, rider shortcut, cancel, undo, and reset for `PuzzleBoard` slider mode while preserving keyboard/mouse behavior.

**Architecture:** Existing `PuzzleBoard` selection and movement remain the single source of truth. New `slider_*` InputMap actions feed a deterministic, explicitly testable selection helper; eligible pieces are filtered by the existing `enable` and `movement_mode` rules; auto-selection is scoped to the board containing/ridden by the player. Existing `undo`/`reset` actions gain gamepad events without losing Z/R.

**Tech Stack:** Godot 4.7, GDScript, `InputMap`, `PuzzleBoard`, headless runtime suite.

**Design source:** `docs/superpowers/specs/2026-10-24-gamepad-slider-controls-design.md`

---

## File Structure

- Modify `project.godot` — add four gamepad-only actions and append gamepad events to `undo`/`reset`.
- Modify `localization/menu.csv` — readable labels for the new and existing slider/history actions.
- Modify `scripts/puzzle/view/puzzle_board.gd` — selection helpers, auto-selection, cycling, rider shortcut, cancel, reset reselect, `_process` wiring.
- Create `tests/puzzle/test_gamepad_selection.gd` — input contract and selection behavior tests.
- Modify `tests/runtime_suite.gd` — register the new test.
- Modify `游戏机制设计.md` — player-facing controller controls.
- Modify `docs/extension-guide.md` — extension contract for the new actions and selection scope.

---

### Task 1: Add gamepad actions and the input contract test

**Files:**
- Modify: `tests/runtime_suite.gd`
- Create: `tests/puzzle/test_gamepad_selection.gd`
- Modify: `project.godot`
- Modify: `localization/menu.csv`

- [ ] **Step 1: Write the failing input-contract test**

Create `tests/puzzle/test_gamepad_selection.gd` with:

```gdscript
extends Node

## Gamepad slider selection: action contract, auto-selection, cycling,
## rider shortcut, cancel, reset, and inactive-board scoping.

const PuzzleBoard := preload("res://scripts/puzzle/view/puzzle_board.gd")
const PuzzlePiece := preload("res://scripts/puzzle/view/puzzle_piece.gd")
const PieceDefinition := preload("res://scripts/puzzle/definition/piece_definition.gd")


func run() -> Array[String]:
	var failures: Array[String] = []
	_assert_gamepad_bindings(failures)
	return failures


func _assert_gamepad_bindings(failures: Array[String]) -> void:
	_assert_joy_button(failures, &"slider_prev", JOY_BUTTON_LEFT_SHOULDER)
	_assert_joy_button(failures, &"slider_next", JOY_BUTTON_RIGHT_SHOULDER)
	_assert_joy_button(failures, &"slider_select_rider", JOY_BUTTON_A)
	_assert_joy_button(failures, &"slider_cancel", JOY_BUTTON_B)
	_assert_joy_button(failures, &"undo", JOY_BUTTON_BACK)
	_assert_joy_button(failures, &"reset", JOY_BUTTON_START)
	_assert_joy_button(failures, &"switch_mode", JOY_BUTTON_Y)
	_assert_key(failures, &"undo", KEY_Z)
	_assert_key(failures, &"reset", KEY_R)
	_assert_key(failures, &"switch_mode", KEY_TAB)


func _assert_joy_button(failures: Array[String], action: StringName, button: int) -> void:
	if not InputMap.has_action(action):
		failures.append("missing gamepad action: %s" % action)
		return
	for event: InputEvent in InputMap.action_get_events(action):
		var joy := event as InputEventJoypadButton
		if joy != null and joy.button_index == button:
			return
	failures.append("%s is not bound to joypad button %d" % [action, button])


func _assert_key(failures: Array[String], action: StringName, keycode: Key) -> void:
	if not InputMap.has_action(action):
		failures.append("missing keyboard action: %s" % action)
		return
	for event: InputEvent in InputMap.action_get_events(action):
		var key := event as InputEventKey
		if key != null and (key.keycode == keycode or key.physical_keycode == keycode):
			return
	failures.append("%s lost its %s keyboard binding" % [action, keycode])
```

Register the file in `tests/runtime_suite.gd` immediately after
`test_piece_enable.gd`:

```gdscript
	preload("res://tests/puzzle/test_piece_enable.gd"),
	preload("res://tests/puzzle/test_gamepad_selection.gd"),
	preload("res://tests/puzzle/test_rider_jump_reset.gd"),
```

- [ ] **Step 2: Run the test and confirm it fails**

Run:

```bash
godot --headless --path . -s res://tests/run_runtime_suite.gd
```

Expected: failure messages for missing `slider_prev`, `slider_next`,
`slider_select_rider`, `slider_cancel`, and missing gamepad events on
`undo`/`reset`.

- [ ] **Step 3: Add the four actions and gamepad events**

Add these actions after the existing `reset` action in `project.godot`:

```text
slider_prev={
"deadzone": 0.2,
"events": [Object(InputEventJoypadButton,"resource_local_to_scene":false,"resource_name":"","device":-1,"button_index":9,"pressure":0.0,"pressed":true,"script":null)
]
}
slider_next={
"deadzone": 0.2,
"events": [Object(InputEventJoypadButton,"resource_local_to_scene":false,"resource_name":"","device":-1,"button_index":10,"pressure":0.0,"pressed":true,"script":null)
]
}
slider_select_rider={
"deadzone": 0.2,
"events": [Object(InputEventJoypadButton,"resource_local_to_scene":false,"resource_name":"","device":-1,"button_index":0,"pressure":0.0,"pressed":true,"script":null)
]
}
slider_cancel={
"deadzone": 0.2,
"events": [Object(InputEventJoypadButton,"resource_local_to_scene":false,"resource_name":"","device":-1,"button_index":1,"pressure":0.0,"pressed":true,"script":null)
]
}
```

Append a Back/View event to the existing `undo` event array:

```text
, Object(InputEventJoypadButton,"resource_local_to_scene":false,"resource_name":"","device":-1,"button_index":4,"pressure":0.0,"pressed":true,"script":null)
```

Append a Start/Menu event to the existing `reset` event array:

```text
, Object(InputEventJoypadButton,"resource_local_to_scene":false,"resource_name":"","device":-1,"button_index":6,"pressure":0.0,"pressed":true,"script":null)
```

- [ ] **Step 4: Add localized action labels**

Add to `localization/menu.csv` after `INPUT_ACTION_INTERACT`:

```text
INPUT_ACTION_SWITCH_MODE,Switch Mode,切换滑块模式
INPUT_ACTION_UNDO,Undo,撤销
INPUT_ACTION_RESET,Reset,重置
INPUT_ACTION_SLIDER_PREV,Previous Slider,上一个滑块
INPUT_ACTION_SLIDER_NEXT,Next Slider,下一个滑块
INPUT_ACTION_SLIDER_SELECT_RIDER,Select Ridden Slider,选中骑乘滑块
INPUT_ACTION_SLIDER_CANCEL,Cancel Selection,取消选中
```

- [ ] **Step 5: Run the contract test and confirm it passes**

Run:

```bash
godot --headless --path . -s res://tests/run_runtime_suite.gd
```

Expected: `EXIT=0`; no missing-action failures.

- [ ] **Step 6: Commit**

```bash
git add project.godot localization/menu.csv tests/puzzle/test_gamepad_selection.gd \
  tests/runtime_suite.gd
git commit -m "feat: add gamepad slider action bindings"
```

---

### Task 2: Implement selection helpers and auto-selection

**Files:**
- Modify: `scripts/puzzle/view/puzzle_board.gd`
- Test: `tests/puzzle/test_gamepad_selection.gd`

- [ ] **Step 1: Replace the empty fixture and add selection tests**

Replace `_make_board()` in `tests/puzzle/test_gamepad_selection.gd` and add these
calls to `run()`:

```gdscript
	_assert_initial_selection(failures)
	_assert_cycle_order(failures)
	_assert_rider_shortcut_and_cancel(failures)
	_assert_inactive_board(failures)
	_assert_reset_reselects(failures)
	_assert_selection_does_not_create_history(failures)
	return failures
```

Add the `PuzzleSession` preload and these test methods:

```gdscript
func _assert_initial_selection(failures: Array[String]) -> void:
	var fixture := _make_board(Vector2i(9, 5))
	var board: PuzzleBoard = fixture.board
	board.call("_enter_drag_mode")
	var selected: PuzzlePiece = board.get("_selected_piece")
	if selected != board.get("_pieces")[0]:
		failures.append("slider mode did not select the first eligible piece")
	_cleanup(fixture)

	fixture = _make_board(Vector2i(6, 0))
	board = fixture.board
	board.call("_enter_drag_mode")
	selected = board.get("_selected_piece")
	if selected != board.get("_pieces")[2]:
		failures.append("slider mode did not select the ridden piece")
	_cleanup(fixture)


func _assert_cycle_order(failures: Array[String]) -> void:
	var fixture := _make_board(Vector2i(9, 5))
	var board: PuzzleBoard = fixture.board
	board.call("_enter_drag_mode")
	if not board.call("_handle_selection_input", false, true, false, false):
		failures.append("RB did not consume the next-piece input")
	var selected: PuzzlePiece = board.get("_selected_piece")
	if selected != board.get("_pieces")[2]:
		failures.append("RB did not skip the disabled piece")
	board.call("_handle_selection_input", false, true, false, false)
	if board.get("_selected_piece") != board.get("_pieces")[4]:
		failures.append("RB did not reach the enabled void piece")
	board.call("_handle_selection_input", false, true, false, false)
	if board.get("_selected_piece") != board.get("_pieces")[0]:
		failures.append("RB did not wrap to the first piece")
	board.call("_handle_selection_input", true, false, false, false)
	if board.get("_selected_piece") != board.get("_pieces")[4]:
		failures.append("LB did not wrap backward")
	_cleanup(fixture)


func _assert_rider_shortcut_and_cancel(failures: Array[String]) -> void:
	var fixture := _make_board(Vector2i(6, 0))
	var board: PuzzleBoard = fixture.board
	board.call("_enter_drag_mode")
	board.call("_handle_selection_input", false, false, false, true)
	if board.get("_selected_piece") != null:
		failures.append("B did not clear the selection")
	board.call("_handle_selection_input", false, false, true, false)
	if board.get("_selected_piece") != board.get("_pieces")[2]:
		failures.append("A did not re-select the ridden piece")
	board.call("_handle_selection_input", false, false, false, true)
	if board.get("_selected_piece") != null:
		failures.append("B did not clear the rider shortcut selection")
	board.call("set_player_to_cell", Vector2i(9, 5))
	board.call("_handle_selection_input", false, false, true, false)
	if board.get("_selected_piece") != null:
		failures.append("A selected a piece when the player was not riding")
	_cleanup(fixture)


func _assert_inactive_board(failures: Array[String]) -> void:
	var fixture := _make_board(Vector2i(20, 20))
	var board: PuzzleBoard = fixture.board
	board.call("_enter_drag_mode")
	if board.get("_selected_piece") != null:
		failures.append("inactive board auto-selected a piece")
	board.call("_handle_selection_input", false, true, true, false)
	if board.get("_selected_piece") != null:
		failures.append("inactive board accepted gamepad selection")
	_cleanup(fixture)


func _assert_reset_reselects(failures: Array[String]) -> void:
	var fixture := _make_board(Vector2i(9, 5))
	var board: PuzzleBoard = fixture.board
	board.call("_enter_drag_mode")
	board.call("_handle_selection_input", false, true, false, false)
	if board.get("_selected_piece") != board.get("_pieces")[2]:
		failures.append("reset fixture did not select the second eligible piece")
	board.call("_reset_puzzle")
	if board.get("_selected_piece") != board.get("_pieces")[0]:
		failures.append("reset did not re-select the first eligible piece")
	_cleanup(fixture)


func _assert_selection_does_not_create_history(failures: Array[String]) -> void:
	var fixture := _make_board(Vector2i(9, 5))
	var board: PuzzleBoard = fixture.board
	board.call("_enter_drag_mode")
	board.call("_handle_selection_input", false, true, false, false)
	var session: PuzzleSession = board.get("session")
	if session.get_move_count() != 0:
		failures.append("selection created a puzzle history entry")
	_cleanup(fixture)


func _make_board(rider_at: Vector2i) -> Dictionary:
	var board := PuzzleBoard.new()
	board.board_size = Vector2i(10, 6)
	board.cell_size = 8
	var specs: Array[Dictionary] = [
		{"cell": Vector2i(2, 1), "enable": true, "mode": PieceDefinition.MovementMode.FREE, "void": false},
		{"cell": Vector2i(4, 1), "enable": false, "mode": PieceDefinition.MovementMode.FREE, "void": false},
		{"cell": Vector2i(6, 1), "enable": true, "mode": PieceDefinition.MovementMode.FREE, "void": false},
		{"cell": Vector2i(8, 1), "enable": true, "mode": PieceDefinition.MovementMode.STATIC, "void": false},
		{"cell": Vector2i(2, 4), "enable": true, "mode": PieceDefinition.MovementMode.FREE, "void": true},
		{"cell": Vector2i(4, 4), "enable": false, "mode": PieceDefinition.MovementMode.FREE, "void": true},
	]
	for spec: Dictionary in specs:
		var piece := PuzzlePiece.new()
		piece.cell_size = 8
		piece.position = Vector2(spec.cell) * 8.0
		piece.polygon = PackedVector2Array([
			Vector2.ZERO,
			Vector2(8.0, 0.0),
			Vector2(8.0, 8.0),
			Vector2(0.0, 8.0),
		])
		piece.enable = bool(spec.enable)
		piece.movement_mode = spec.mode
		piece.is_void = bool(spec.void)
		board.add_child(piece)
	add_child(board)
	var player := Node2D.new()
	player.name = "TestPlayer"
	player.add_to_group("player")
	add_child(player)
	board.set("_player", player)
	board.call("set_player_to_cell", rider_at)
	return {"board": board, "player": player}


func _cleanup(fixture: Dictionary) -> void:
	(fixture.board as PuzzleBoard).free()
	(fixture.player as Node2D).free()
```

- [ ] **Step 2: Run the suite and confirm the selection tests fail**

Run:

```bash
godot --headless --path . -s res://tests/run_runtime_suite.gd
```

Expected: failures for auto-selection, `_handle_selection_input`, reset
re-selection, and no history changes.

- [ ] **Step 3: Add the selection helpers**

Add exports near the existing action exports:

```gdscript
@export var prev_piece_action: StringName = &"slider_prev"
@export var next_piece_action: StringName = &"slider_next"
@export var select_rider_action: StringName = &"slider_select_rider"
@export var cancel_selection_action: StringName = &"slider_cancel"
```

Add these methods after `_is_player_inside_board_rect()`:

```gdscript
func _is_selection_active() -> bool:
	if _player == null or not is_instance_valid(_player):
		return false
	if _is_player_inside_board_rect():
		return true
	for piece in _pieces:
		if not piece.is_void and _player_rides(piece):
			return true
	return false


func _controllable_pieces() -> Array[PuzzlePiece]:
	var result: Array[PuzzlePiece] = []
	for piece in _pieces:
		if _can_drag_piece(piece):
			result.append(piece)
	return result


func _select_initial_piece() -> void:
	if mode != ControlMode.DRAG:
		return
	if not _is_selection_active():
		_deselect_piece(true)
		return
	var candidates := _controllable_pieces()
	if candidates.is_empty():
		_deselect_piece(true)
		return
	for piece in candidates:
		if _player_rides(piece):
			_select_piece(piece)
			return
	_select_piece(candidates[0])


func _cycle_selection(direction: int) -> bool:
	if mode != ControlMode.DRAG or direction == 0 or not _is_selection_active():
		return false
	var candidates := _controllable_pieces()
	if candidates.is_empty():
		return false
	var index := candidates.find(_selected_piece)
	var target_index: int
	if index < 0:
		target_index = 0 if direction > 0 else candidates.size() - 1
	else:
		target_index = (index + direction + candidates.size()) % candidates.size()
	_select_piece(candidates[target_index])
	return true


func _select_rider_piece() -> bool:
	if mode != ControlMode.DRAG or not _is_selection_active():
		return false
	for piece in _controllable_pieces():
		if _player_rides(piece):
			_select_piece(piece)
			return true
	return false


func _cancel_selection() -> bool:
	if mode != ControlMode.DRAG or not _is_selection_active():
		return false
	_deselect_piece()
	return true


func _handle_selection_input(
	previous_pressed: bool,
	next_pressed: bool,
	select_pressed: bool,
	cancel_pressed: bool
) -> bool:
	if mode != ControlMode.DRAG:
		return false
	if select_pressed:
		_select_rider_piece()
		return true
	if next_pressed:
		_cycle_selection(1)
		return true
	if previous_pressed:
		_cycle_selection(-1)
		return true
	if cancel_pressed:
		_cancel_selection()
		return true
	return false
```

- [ ] **Step 4: Wire auto-selection and reset re-selection**

In `_enter_drag_mode()`, call `_select_initial_piece()` after locking the player:

```gdscript
func _enter_drag_mode() -> void:
	mode = ControlMode.DRAG
	_carried_during_drag = false
	_lock_player(true)
	if _mode_overlay != null:
		_mode_overlay.set_active(true)
	_select_initial_piece()
```

Replace `_reset_puzzle()` with:

```gdscript
func _reset_puzzle() -> void:
	if session == null:
		return
	var did_reset := session.reset()
	if did_reset:
		_deselect_piece(true)
		_end_drag()
		_hide_preview()
		_sync_pieces_from_state(true)
	if mode == ControlMode.DRAG:
		_select_initial_piece()
```

- [ ] **Step 5: Run the selection tests and confirm they pass**

Run:

```bash
godot --headless --path . -s res://tests/run_runtime_suite.gd
```

Expected: `EXIT=0`; all selection tests pass, existing tests unchanged.

- [ ] **Step 6: Commit**

```bash
git add scripts/puzzle/view/puzzle_board.gd tests/puzzle/test_gamepad_selection.gd
git commit -m "feat: add gamepad slider selection model"
```

---

### Task 3: Wire live gamepad input and document the controls

**Files:**
- Modify: `scripts/puzzle/view/puzzle_board.gd`
- Modify: `游戏机制设计.md`
- Modify: `docs/extension-guide.md`

- [ ] **Step 1: Add a source-level assertion for live input wiring**

In `tests/puzzle/test_gamepad_selection.gd`, add this to `run()`:

```gdscript
	_assert_process_wiring(failures)
```

Add:

```gdscript
func _assert_process_wiring(failures: Array[String]) -> void:
	var source := FileAccess.get_file_as_string("res://scripts/puzzle/view/puzzle_board.gd")
	for action: StringName in [
		&"prev_piece_action",
		&"next_piece_action",
		&"select_rider_action",
		&"cancel_selection_action",
	]:
		if not source.contains(String(action)):
			failures.append("PuzzleBoard is missing live action export %s" % action)
	if not source.contains("_handle_selection_input("):
		failures.append("PuzzleBoard does not call the selection input seam")
	if not source.contains("Input.is_action_just_pressed"):
		failures.append("PuzzleBoard does not read live Input actions")
```

- [ ] **Step 2: Run the test and confirm it fails**

Run:

```bash
godot --headless --path . -s res://tests/run_runtime_suite.gd
```

Expected: failure because `_process()` does not yet read the four action names.

- [ ] **Step 3: Wire `_process()`**

In `_process()`, after the mode-switch block and before `_handle_mouse()`, add:

```gdscript
	if mode == ControlMode.DRAG:
		_handle_selection_input(
			Input.is_action_just_pressed(String(prev_piece_action)),
			Input.is_action_just_pressed(String(next_piece_action)),
			Input.is_action_just_pressed(String(select_rider_action)),
			Input.is_action_just_pressed(String(cancel_selection_action))
		)
```

The final order in `_process()` must be: history, switch, selection,
mouse, movement. Keep the existing `if _handle_history_input(...): return`.

- [ ] **Step 4: Document player-facing controls**

Add to `游戏机制设计.md` after the keyboard/mouse slider controls:

```markdown
### 手柄操作
- `Y`：进入 / 退出滑块模式。
- `LB` / `RB`：按场景顺序循环选中可控制滑块；跳过 `enable = false` 和 `STATIC`。
- `D-pad` / 左摇杆：移动当前选中滑块。
- `A`：重新选中玩家正在骑乘的滑块。
- `B`：取消选中。
- `Back` / `View`：撤销。
- `Start` / `Menu`：重置棋盘。
- 进入滑块模式时优先自动选中玩家骑乘的滑块，否则选中第一个可控制滑块。
- 选择输入只对包含玩家或玩家正在骑乘其滑块的棋盘生效；禁用虚空滑块不进入循环，但仍可被被动推动。
```

Add to `docs/extension-guide.md` under `Puzzle Sliding Regions`:

```markdown
- Gamepad selection uses the project actions `slider_prev`, `slider_next`,
  `slider_select_rider`, and `slider_cancel`. `PuzzleBoard` filters these to
  `enable` + non-`STATIC` pieces in scene order. Entering drag mode auto-selects
  the ridden piece, or the first eligible piece. Controller selection is scoped
  to the board containing the player or a board the player is riding.
- `undo` keeps Z and gains Back/View; `reset` keeps R and gains Start/Menu.
  New slider actions have no keyboard defaults; assign them through the existing
  Input Mapping menu if needed.
- Test selection through `PuzzleBoard._handle_selection_input(previous, next,
  select, cancel)` with explicit booleans. Do not rely on
  `Input.action_press()` edge timing in headless tests.
```

- [ ] **Step 5: Run the full suite and validate the project**

Run:

```bash
godot --headless --path . -s res://tests/run_runtime_suite.gd
godot --headless --path . -s res://tools/validate_project.gd
```

Expected: both `EXIT=0`.

- [ ] **Step 6: Commit**

```bash
git add scripts/puzzle/view/puzzle_board.gd tests/puzzle/test_gamepad_selection.gd \
  游戏机制设计.md docs/extension-guide.md
git commit -m "feat: wire gamepad slider controls"
```

---

### Task 4: Final verification and manual acceptance

**Files:**
- Modify: `docs/superpowers/plans/2026-10-24-gamepad-slider-controls.md` (status only)

- [ ] **Step 1: Run the suite twice**

```bash
for i in 1 2; do
  godot --headless --path . -s res://tests/run_runtime_suite.gd
  echo "EXIT=$?"
done
```

Expected: both runs `EXIT=0`.

- [ ] **Step 2: Run project validation**

```bash
godot --headless --path . -s res://tools/validate_project.gd
```

Expected: `EXIT=0`.

- [ ] **Step 3: Update the plan status**

Change the plan header status to `Implemented and verified on 2026-10-24` and
record that the runtime suite passed twice and project validation passed.

- [ ] **Step 4: Manual controller test (user)**

Ask the user to run `room_start_00.tscn` with a controller and verify:

- Y enters/exits slider mode;
- auto-selection and LB/RB wrap/skip disabled pieces;
- A selects the ridden piece, B clears;
- D-pad and left stick move exactly one step per press;
- Back undoes, Start resets and re-selects;
- mouse/keyboard and disabled-void passive pushes still work.

- [ ] **Step 5: Commit the verification note**

```bash
git add docs/superpowers/plans/2026-10-24-gamepad-slider-controls.md
git commit -m "docs: verify gamepad slider controls"
```

---

## Self-Review

- **Spec coverage:** input actions, auto-selection, scene-order cycling,
  disabled/static skipping, rider shortcut, cancel, reset reselect, multi-board
  scope, documentation, and tests all have explicit tasks.
- **Placeholders:** none; every code step includes concrete code.
- **Type consistency:** `_handle_selection_input(previous, next, select, cancel)`
  uses one signature everywhere; `direction` is an integer; all preloads are
  defined before use; `PuzzleSession` is preloaded in the test.
- **Known test constraint:** headless tests call the explicit boolean seam rather
  than relying on `Input.action_press()` edge timing.
