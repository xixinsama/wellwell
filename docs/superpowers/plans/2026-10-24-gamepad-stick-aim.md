# Gamepad Right-Stick Aim Selection Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the right stick preview and select the nearest eligible slider in a 45-degree direction cone, with release-to-switch behavior and an aim arrow.

**Architecture:** Add four right-stick InputMap actions, a runtime-only `PuzzleAimArrow` Node2D, and pure board helpers that return a target for an explicit aim vector. Directional selection filters through the existing `_controllable_pieces()` list, so `enable` and `STATIC` rules stay authoritative. Release uses the last displayed target and never creates history.

**Tech Stack:** Godot 4.7, GDScript, `Input.get_vector`, `InputEventJoypadMotion`, headless runtime suite.

**Design source:** `docs/superpowers/specs/2026-10-24-gamepad-stick-aim-design.md`

---

## File Structure

- Modify `project.godot` — add `aim_left/right/up/down` right-stick actions.
- Modify `localization/menu.csv` — labels for the four aim actions.
- Create `scripts/puzzle/view/puzzle_aim_arrow.gd` — arrow renderer.
- Create `tests/puzzle/test_gamepad_stick_aim.gd` — aim bindings, target, arrow, release tests.
- Modify `tests/runtime_suite.gd` — register the aim test.
- Modify `scripts/puzzle/view/puzzle_board.gd` — exports, arrow child, aim helpers, process wiring.
- Modify `游戏机制设计.md` and `docs/extension-guide.md` — player and extension docs.

---

### Task 1: Add right-stick actions and their contract test

**Files:**
- Modify: `tests/runtime_suite.gd`
- Create: `tests/puzzle/test_gamepad_stick_aim.gd`
- Modify: `project.godot`
- Modify: `localization/menu.csv`

- [ ] **Step 1: Write the failing action-binding test**

Create `tests/puzzle/test_gamepad_stick_aim.gd`:

```gdscript
extends Node

## Right-stick aim target selection and release-to-switch behavior.

const PuzzleBoard := preload("res://scripts/puzzle/view/puzzle_board.gd")
const PuzzlePiece := preload("res://scripts/puzzle/view/puzzle_piece.gd")
const PieceDefinition := preload("res://scripts/puzzle/definition/piece_definition.gd")


func run() -> Array[String]:
	var failures: Array[String] = []
	_assert_aim_bindings(failures)
	return failures


func _assert_aim_bindings(failures: Array[String]) -> void:
	_assert_joy_axis(failures, &"aim_left", JOY_AXIS_RIGHT_X, -1.0)
	_assert_joy_axis(failures, &"aim_right", JOY_AXIS_RIGHT_X, 1.0)
	_assert_joy_axis(failures, &"aim_up", JOY_AXIS_RIGHT_Y, -1.0)
	_assert_joy_axis(failures, &"aim_down", JOY_AXIS_RIGHT_Y, 1.0)


func _assert_joy_axis(
	failures: Array[String],
	action: StringName,
	axis: JoyAxis,
	value: float
) -> void:
	if not InputMap.has_action(action):
		failures.append("missing aim action: %s" % action)
		return
	for event: InputEvent in InputMap.action_get_events(action):
		var motion := event as InputEventJoypadMotion
		if motion != null and motion.axis == axis and is_equal_approx(motion.axis_value, value):
			return
	failures.append("%s is not bound to right-stick axis %d value %.1f" % [action, axis, value])


func _make_board() -> Dictionary:
	return {}
```

Register it in `tests/runtime_suite.gd` after `test_gamepad_selection.gd`:

```gdscript
	preload("res://tests/puzzle/test_gamepad_selection.gd"),
	preload("res://tests/puzzle/test_gamepad_stick_aim.gd"),
	preload("res://tests/puzzle/test_rider_jump_reset.gd"),
```

- [ ] **Step 2: Run the test and confirm it fails**

```bash
godot --headless --path . -s res://tests/run_runtime_suite.gd
```

Expected: missing `aim_left`, `aim_right`, `aim_up`, `aim_down`.

- [ ] **Step 3: Add the actions**

Add after `slider_cancel` in `project.godot`:

```text
aim_left={
"deadzone": 0.2,
"events": [Object(InputEventJoypadMotion,"resource_local_to_scene":false,"resource_name":"","device":-1,"axis":2,"axis_value":-1.0,"script":null)
]
}
aim_right={
"deadzone": 0.2,
"events": [Object(InputEventJoypadMotion,"resource_local_to_scene":false,"resource_name":"","device":-1,"axis":2,"axis_value":1.0,"script":null)
]
}
aim_up={
"deadzone": 0.2,
"events": [Object(InputEventJoypadMotion,"resource_local_to_scene":false,"resource_name":"","device":-1,"axis":3,"axis_value":-1.0,"script":null)
]
}
aim_down={
"deadzone": 0.2,
"events": [Object(InputEventJoypadMotion,"resource_local_to_scene":false,"resource_name":"","device":-1,"axis":3,"axis_value":1.0,"script":null)
]
}
```

- [ ] **Step 4: Add labels**

Add to `localization/menu.csv` after the slider labels:

```text
INPUT_ACTION_AIM_LEFT,Aim Left,右摇杆向左
INPUT_ACTION_AIM_RIGHT,Aim Right,右摇杆向右
INPUT_ACTION_AIM_UP,Aim Up,右摇杆向上
INPUT_ACTION_AIM_DOWN,Aim Down,右摇杆向下
```

- [ ] **Step 5: Run the contract test and commit**

```bash
godot --headless --path . -s res://tests/run_runtime_suite.gd
# EXIT=0
git add project.godot localization/menu.csv tests/puzzle/test_gamepad_stick_aim.gd \
  tests/runtime_suite.gd
git commit -m "feat: add right-stick aim actions"
```

---

### Task 2: Add the aim arrow and target geometry

**Files:**
- Create: `scripts/puzzle/view/puzzle_aim_arrow.gd`
- Modify: `scripts/puzzle/view/puzzle_board.gd`
- Test: `tests/puzzle/test_gamepad_stick_aim.gd`

- [ ] **Step 1: Add failing target and arrow tests**

Replace `_make_board()` in `tests/puzzle/test_gamepad_stick_aim.gd` with:

```gdscript
func _make_board() -> Dictionary:
	var board := PuzzleBoard.new()
	board.board_size = Vector2i(10, 6)
	board.cell_size = 8
	var specs: Array[Dictionary] = [
		{"cell": Vector2i(2, 1), "enable": true, "mode": PieceDefinition.MovementMode.FREE},
		{"cell": Vector2i(4, 1), "enable": false, "mode": PieceDefinition.MovementMode.FREE},
		{"cell": Vector2i(6, 1), "enable": true, "mode": PieceDefinition.MovementMode.FREE},
		{"cell": Vector2i(2, 4), "enable": true, "mode": PieceDefinition.MovementMode.FREE},
		{"cell": Vector2i(8, 1), "enable": true, "mode": PieceDefinition.MovementMode.STATIC},
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
		board.add_child(piece)
	add_child(board)
	var player := Node2D.new()
	player.add_to_group("player")
	add_child(player)
	board.set("_player", player)
	board.call("set_player_to_cell", Vector2i(9, 5))
	return {"board": board, "player": player}
```

Add calls to `run()`:

```gdscript
	_assert_right_target_and_arrow(failures)
	_assert_release_switches(failures)
	_assert_no_target_release(failures)
	_assert_cancel_discards_target(failures)
	_assert_mode_exit_discards_target(failures)
	return failures
```

Add helpers:

```gdscript
func _assert_right_target_and_arrow(failures: Array[String]) -> void:
	var fixture := _make_board()
	var board: PuzzleBoard = fixture.board
	board.call("_enter_drag_mode")
	board.call("_handle_stick_selection", Vector2.RIGHT)
	var target: PuzzlePiece = board.get("_stick_target")
	if target != board.get("_pieces")[2]:
		failures.append("right aim did not skip the disabled piece to the nearest enabled piece")
	var arrow = board.get("_aim_arrow")
	if arrow == null or not arrow.visible:
		failures.append("right aim did not show the arrow")
	else:
		var points: PackedVector2Array = arrow.call("get_aim_points")
		if points.size() != 2 or not points[0].is_equal_approx(Vector2(20, 12)):
			failures.append("aim arrow did not start at the selected piece center")
		if not points[1].is_equal_approx(Vector2(52, 12)):
			failures.append("aim arrow did not end at the target piece center")
	_cleanup(fixture)


func _assert_release_switches(failures: Array[String]) -> void:
	var fixture := _make_board()
	var board: PuzzleBoard = fixture.board
	board.call("_enter_drag_mode")
	board.call("_handle_stick_selection", Vector2.RIGHT)
	board.call("_handle_stick_selection", Vector2.ZERO)
	if board.get("_selected_piece") != board.get("_pieces")[2]:
		failures.append("releasing the stick did not switch to the aimed piece")
	var arrow = board.get("_aim_arrow")
	if arrow != null and arrow.visible:
		failures.append("releasing the stick left the aim arrow visible")
	_cleanup(fixture)


func _assert_no_target_release(failures: Array[String]) -> void:
	var fixture := _make_board()
	var board: PuzzleBoard = fixture.board
	board.call("_enter_drag_mode")
	board.call("_handle_stick_selection", Vector2.UP)
	if board.get("_stick_target") != null:
		failures.append("up aim found a target when no piece was above")
	board.call("_handle_stick_selection", Vector2.ZERO)
	if board.get("_selected_piece") != board.get("_pieces")[0]:
		failures.append("release without a target changed the selection")
	_cleanup(fixture)


func _assert_cancel_discards_target(failures: Array[String]) -> void:
	var fixture := _make_board()
	var board: PuzzleBoard = fixture.board
	board.call("_enter_drag_mode")
	board.call("_handle_stick_selection", Vector2.RIGHT)
	board.call("_handle_selection_input", false, false, false, true)
	if board.get("_selected_piece") != null or board.get("_stick_target") != null:
		failures.append("cancel did not clear the pending aim target")
	board.call("_handle_stick_selection", Vector2.ZERO)
	if board.get("_selected_piece") != null:
		failures.append("release after cancel switched to a discarded target")
	_cleanup(fixture)


func _assert_mode_exit_discards_target(failures: Array[String]) -> void:
	var fixture := _make_board()
	var board: PuzzleBoard = fixture.board
	board.call("_enter_drag_mode")
	board.call("_handle_stick_selection", Vector2.RIGHT)
	board.call("_exit_drag_mode")
	var arrow = board.get("_aim_arrow")
	if board.get("_stick_target") != null or (arrow != null and arrow.visible):
		failures.append("mode exit did not clear the aim target and arrow")
	_cleanup(fixture)


func _cleanup(fixture: Dictionary) -> void:
	(fixture.board as PuzzleBoard).free()
	(fixture.player as Node2D).free()
```

- [ ] **Step 2: Run the suite and confirm target tests fail**

```bash
godot --headless --path . -s res://tests/run_runtime_suite.gd
```

Expected: failures for missing `_handle_stick_selection`, `_stick_target`, and
`_aim_arrow`.

- [ ] **Step 3: Create `PuzzleAimArrow`**

Create `scripts/puzzle/view/puzzle_aim_arrow.gd`:

```gdscript
class_name PuzzleAimArrow
extends Node2D

## Runtime-only arrow preview from the selected slider to the right-stick target.

const LINE_COLOR := Color(1.0, 0.94, 0.52, 0.95)
const LINE_WIDTH := 1.0
const HEAD_LENGTH := 5.0
const HEAD_WIDTH := 4.0

var _from := Vector2.ZERO
var _to := Vector2.ZERO
var _has_target := false


func setup() -> void:
	z_index = 20
	visible = false
	queue_redraw()


func show_between(from_point: Vector2, to_point: Vector2) -> void:
	_from = from_point
	_to = to_point
	_has_target = true
	visible = true
	queue_redraw()


func hide_arrow() -> void:
	_has_target = false
	visible = false
	queue_redraw()


func get_aim_points() -> PackedVector2Array:
	return PackedVector2Array([_from, _to])


func _draw() -> void:
	if not _has_target:
		return
	var delta := _to - _from
	if delta.length_squared() <= 0.0001:
		return
	var direction := delta.normalized()
	draw_line(_from, _to, LINE_COLOR, LINE_WIDTH)
	var base := _to - direction * HEAD_LENGTH
	var perpendicular := Vector2(-direction.y, direction.x) * (HEAD_WIDTH * 0.5)
	draw_colored_polygon(
		PackedVector2Array([_to, base + perpendicular, base - perpendicular]),
		LINE_COLOR
	)
```

- [ ] **Step 4: Add board target geometry and arrow child**

At the top of `puzzle_board.gd`, add the preload and constants:

```gdscript
const AIM_ARROW_SCRIPT := preload("res://scripts/puzzle/view/puzzle_aim_arrow.gd")
const AIM_DEADZONE := 0.3
const AIM_MIN_DOT := 0.7071068
```

Add exports near the other action exports:

```gdscript
@export var aim_left_action: StringName = &"aim_left"
@export var aim_right_action: StringName = &"aim_right"
@export var aim_up_action: StringName = &"aim_up"
@export var aim_down_action: StringName = &"aim_down"
```

Add the arrow state and child:

```gdscript
var _aim_arrow: PuzzleAimArrow = null
var _stick_target: PuzzlePiece = null
```

In `_ready()`, after `_build_mode_overlay()`:

```gdscript
	_build_aim_arrow()
```

Add methods near `_build_mode_overlay()`:

```gdscript
func _build_aim_arrow() -> void:
	_aim_arrow = AIM_ARROW_SCRIPT.new() as PuzzleAimArrow
	_aim_arrow.name = "AimArrow"
	_aim_arrow.setup()
	add_child(_aim_arrow)


func _read_stick_aim() -> Vector2:
	return Input.get_vector(
		String(aim_left_action),
		String(aim_right_action),
		String(aim_up_action),
		String(aim_down_action)
	)


func _handle_stick_selection(aim: Vector2) -> void:
	if mode != ControlMode.DRAG or not _is_selection_active() or _selected_piece == null:
		_clear_stick_aim()
		return
	if aim.length() < AIM_DEADZONE:
		_release_stick_selection()
		return
	_stick_target = _find_directional_target(_selected_piece, aim)
	if _aim_arrow == null:
		return
	if _stick_target == null:
		_aim_arrow.hide_arrow()
	else:
		_aim_arrow.show_between(
			_piece_center(_selected_piece),
			_piece_center(_stick_target)
		)


func _release_stick_selection() -> void:
	var target := _stick_target
	_clear_stick_aim()
	if target != null and is_instance_valid(target) and _can_drag_piece(target):
		_select_piece(target)


func _clear_stick_aim() -> void:
	_stick_target = null
	if _aim_arrow != null:
		_aim_arrow.hide_arrow()


func _find_directional_target(selected: PuzzlePiece, aim: Vector2) -> PuzzlePiece:
	if selected == null or aim.length_squared() <= 0.0001:
		return null
	var aim_dir := aim.normalized()
	var origin := _piece_center(selected)
	var best: PuzzlePiece = null
	var best_distance_sq := INF
	for piece in _controllable_pieces():
		if piece == selected:
			continue
		var delta := _piece_center(piece) - origin
		var distance_sq := delta.length_squared()
		if distance_sq <= 0.0001:
			continue
		var alignment := aim_dir.dot(delta / sqrt(distance_sq))
		if alignment < AIM_MIN_DOT:
			continue
		if distance_sq < best_distance_sq:
			best_distance_sq = distance_sq
			best = piece
	return best


func _piece_center(piece: PuzzlePiece) -> Vector2:
	var bounds := piece.get_bounds()
	var center_offset := Vector2(bounds.position) + Vector2(bounds.size) * 0.5
	return piece.position + center_offset * float(cell_size)
```

Call `_clear_stick_aim()` from `_enter_drag_mode()` and after the successful
guard in `_exit_drag_mode()`:

```gdscript
func _enter_drag_mode() -> void:
	mode = ControlMode.DRAG
	_carried_during_drag = false
	_clear_stick_aim()
	_lock_player(true)
	if _mode_overlay != null:
		_mode_overlay.set_active(true)
	_select_initial_piece()
```

```gdscript
func _exit_drag_mode(force: bool = false) -> void:
	if not force and (_player_cell_inside_void() or _player_cell_inside_piece()):
		return
	var grant_air_jump := _carried_during_drag and not force
	_carried_during_drag = false
	_clear_stick_aim()
	mode = ControlMode.JUMP
	...
```

Call `_clear_stick_aim()` at the start of both `_select_piece()` and
`_deselect_piece()` after their validity guards:

```gdscript
func _select_piece(piece: PuzzlePiece) -> void:
	if not _can_drag_piece(piece):
		return
	_clear_stick_aim()
	if _selected_piece == piece:
		return
	...
```

```gdscript
func _deselect_piece(force: bool = false) -> void:
	if not force and _player_cell_inside_void() and _attached_piece != null:
		return
	_clear_stick_aim()
	_selected_piece = null
	...
```

- [ ] **Step 5: Run the target tests and commit**

```bash
godot --headless --path . -s res://tests/run_runtime_suite.gd
# EXIT=0
git add scripts/puzzle/view/puzzle_aim_arrow.gd scripts/puzzle/view/puzzle_aim_arrow.gd.uid \
  scripts/puzzle/view/puzzle_board.gd tests/puzzle/test_gamepad_stick_aim.gd
git commit -m "feat: add right-stick aim target and arrow"
```

---

### Task 3: Wire live right-stick input, document, and verify

**Files:**
- Modify: `scripts/puzzle/view/puzzle_board.gd`
- Modify: `游戏机制设计.md`
- Modify: `docs/extension-guide.md`
- Test: `tests/puzzle/test_gamepad_stick_aim.gd`

- [ ] **Step 1: Add the live wiring assertion**

Add `_assert_live_wiring(failures)` to `run()` and these assertions:

```gdscript
func _assert_live_wiring(failures: Array[String]) -> void:
	var source := FileAccess.get_file_as_string("res://scripts/puzzle/view/puzzle_board.gd")
	if not source.contains("_read_stick_aim()"):
		failures.append("PuzzleBoard does not read the right-stick aim vector")
	for action: StringName in [
		&"aim_left_action",
		&"aim_right_action",
		&"aim_up_action",
		&"aim_down_action",
	]:
		if not source.contains(String(action)):
			failures.append("PuzzleBoard is missing live aim action %s" % action)
	if not source.contains("_handle_stick_selection(_read_stick_aim())"):
		failures.append("PuzzleBoard does not poll the right stick in _process")
```

- [ ] **Step 2: Confirm the wiring test fails**

```bash
godot --headless --path . -s res://tests/run_runtime_suite.gd
```

Expected: failure for missing live right-stick polling.

- [ ] **Step 3: Wire `_process()`**

After the button selection block, still inside `if mode == ControlMode.DRAG:`, add:

```gdscript
		_handle_stick_selection(_read_stick_aim())
```

The order must be selection buttons, then stick aim, then `_handle_mouse()`,
then movement.

- [ ] **Step 4: Document controls and extension contract**

Add to `游戏机制设计.md` under the gamepad section:

```markdown
- 右摇杆：偏离中心后从当前选中滑块的中心显示箭头，指向 45° 方向锥内最近的
  可控制滑块中心；松开右摇杆时切换到该目标。没有目标、取消、退出模式或重置
  时不会切换。
```

Add to `docs/extension-guide.md` under `Puzzle Sliding Regions`:

```markdown
- Right-stick aiming uses `aim_left/right/up/down` actions and
  `PuzzleBoard._handle_stick_selection(aim)`. The board chooses the nearest
  `_controllable_pieces()` center inside a 45-degree cone, draws
  `PuzzleAimArrow`, and switches selection only on release. The explicit aim
  vector is the test seam; no history entry is created.
```

- [ ] **Step 5: Run full verification**

```bash
for i in 1 2; do
  godot --headless --path . -s res://tests/run_runtime_suite.gd
  echo "EXIT=$?"
done
godot --headless --path . -s res://tools/validate_project.gd
```

Expected: `EXIT=0` for all three runs.

- [ ] **Step 6: Commit**

```bash
git add scripts/puzzle/view/puzzle_board.gd tests/puzzle/test_gamepad_stick_aim.gd \
  游戏机制设计.md docs/extension-guide.md
git commit -m "feat: wire right-stick aim selection"
```

---

## Self-Review

- **Spec coverage:** right-stick actions, 45-degree target cone, nearest eligible
  center, arrow endpoints, release switching, no-target/cancel/exit behavior,
  disabled/static skipping, docs, and tests all have tasks.
- **Placeholders:** none; all test and implementation code is concrete.
- **Type consistency:** `_handle_stick_selection(aim: Vector2)`,
  `_find_directional_target(selected, aim)`, `_piece_center(piece)`, and
  `PuzzleAimArrow.get_aim_points()` signatures match every use.
- **Test seam:** tests call the explicit `aim` vector; they do not depend on
  physical right-stick state or `Input.action_press()` timing.
