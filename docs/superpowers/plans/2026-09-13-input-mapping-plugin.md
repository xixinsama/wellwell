# Input Mapping Plugin Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a reusable Godot 4 input-remapping addon and integrate its four-column bilingual menu into Wellwell's existing Settings screen.

**Architecture:** A runtime-neutral model class owns action discovery, event classification, normalization, and slot reconstruction. An autoload service owns authored defaults, live `InputMap` mutation, and a versioned `ConfigFile` store; reusable controls bind only to that public service contract. Wellwell instantiates the addon menu, supplies action translations and theme inheritance, and routes Settings navigation and global reset.

**Tech Stack:** Godot 4.7, typed GDScript, Control scenes, `InputMap`, `ProjectSettings`, `ConfigFile`, the repository's `run() -> Array[String]` runtime-test harness.

**Spec:** `docs/superpowers/specs/2026-09-12-input-mapping-plugin-design.md`

## Global Constraints

- The visible layout is `Action | Primary | Secondary | Gamepad`; the final three cells are clickable binding schemes.
- Discover custom actions from explicit `input/*` ProjectSettings entries and keep project order unless menu configuration changes it.
- Treat the first keyboard/mouse event as Primary, remaining keyboard/mouse events as Secondary, and all joypad events as Gamepad.
- Duplicate bindings across actions remain valid.
- Save player overrides to `user://input_mappings.cfg`; never write player choices to `project.godot`.
- Capture accepts keyboard/mouse only for keyboard slots and joypad button/axis only for Gamepad; axis threshold is `0.5` and saved direction is normalized to `-1.0` or `1.0`.
- Escape cancels capture; Backspace/Delete clears the active slot.
- Plugin-owned UI and Wellwell action names support exactly `en` and `zh_CN` in this phase.
- Preserve the user's existing uncommitted `project.godot` Input Map edits and unrelated `addons/platformer_kit/world/entities/save_point.tscn` edit.
- Add every new runtime test script to `tests/runtime_suite.gd`.

## File Structure

- `addons/input_mapping/core/input_mapping_model.gd`: pure discovery, classification, compatibility, normalization, and event-list reconstruction.
- `addons/input_mapping/core/input_mapping_store.gd`: version-1 `ConfigFile` load/save/clear boundary.
- `addons/input_mapping/runtime/input_mapping_service.gd`: defaults snapshot, override validation/application, `InputMap` mutation, persistence signals, and addon translation registration.
- `addons/input_mapping/ui/input_event_formatter.gd`: compact localized event labels.
- `addons/input_mapping/ui/input_binding_button.gd`: one slot's display and capture state.
- `addons/input_mapping/ui/input_binding_button.tscn`: reusable binding button scene.
- `addons/input_mapping/ui/input_mapping_menu.gd`: action filtering/order, dynamic rows, focus, reset, status, and back routing.
- `addons/input_mapping/ui/input_mapping_menu.tscn`: reusable full-screen four-column menu.
- `addons/input_mapping/translations/input_mapping.csv`: addon-owned English and Simplified Chinese messages.
- `addons/input_mapping/input_mapping_plugin.gd` and `plugin.cfg`: autoload registration.
- `addons/input_mapping/README.md`: installation, public API, configuration, and localization convention.
- `tests/input_mapping/test_input_mapping_model.gd`: model behavior.
- `tests/input_mapping/test_input_mapping_service.gd`: persistence and live-map behavior.
- `tests/input_mapping/test_input_mapping_ui.gd`: scene, row, capture, and translation contracts.
- `tests/ui/test_menu_features.gd`: Wellwell navigation, reset, and action-translation integration.
- `tests/ui/capture_menu.gd`: bilingual screenshot route for the new screen.
- `scripts/ui/settings_menu.gd`, `scenes/ui/settings.tscn`, `localization/menu.csv`: host integration.
- `project.godot`: enable the addon and register its autoload without rewriting the user's Input Map hunks.

---

### Task 1: Input Mapping Model

**Files:**
- Create: `addons/input_mapping/core/input_mapping_model.gd`
- Create: `tests/input_mapping/test_input_mapping_model.gd`
- Modify: `tests/runtime_suite.gd`

**Interfaces:**
- Produces: `InputMappingModel.BindingSlot`, `discover_project_actions(...)`, `classify_events(...)`, `get_slot_events(...)`, `is_event_compatible(...)`, `normalize_event(...)`, and `replace_slot_events(...)`.
- Consumes: Godot `ProjectSettings`, `InputMap`, and `InputEvent` subclasses only.

- [ ] **Step 1: Write the failing model tests**

Create a runtime test that uses literal expected action order and real `InputEvent` instances. It must assert these independently observable behaviors:

```gdscript
extends Node

const MODEL := preload("res://addons/input_mapping/core/input_mapping_model.gd")

func run() -> Array[String]:
	var failures: Array[String] = []
	_assert_event_classification(failures)
	_assert_slot_replacement(failures)
	_assert_capture_compatibility_and_axis_normalization(failures)
	_assert_action_filtering_and_order(failures)
	return failures

func _assert_event_classification(failures: Array[String]) -> void:
	var key_a := InputEventKey.new()
	key_a.physical_keycode = KEY_A
	var key_left := InputEventKey.new()
	key_left.physical_keycode = KEY_LEFT
	var pad_button := InputEventJoypadButton.new()
	pad_button.button_index = JOY_BUTTON_DPAD_LEFT
	var pad_axis := InputEventJoypadMotion.new()
	pad_axis.axis = JOY_AXIS_LEFT_X
	pad_axis.axis_value = -1.0
	var groups: Dictionary = MODEL.classify_events([key_a, pad_axis, key_left, pad_button])
	if groups[MODEL.BindingSlot.KEYBOARD_PRIMARY] != [key_a]:
		failures.append("first keyboard event was not classified as primary")
	if groups[MODEL.BindingSlot.KEYBOARD_SECONDARY] != [key_left]:
		failures.append("remaining keyboard events were not classified as secondary")
	if groups[MODEL.BindingSlot.GAMEPAD] != [pad_axis, pad_button]:
		failures.append("joypad events did not retain relative order in the gamepad scheme")
```

The replacement test must prove that replacing Primary preserves Secondary and Gamepad, while replacing Secondary or Gamepad removes the whole old group. The compatibility test must prove a mouse press is accepted by keyboard slots, rejected by Gamepad, and a `0.49` axis is rejected while `-0.75` normalizes to `-1.0`. The ordering test passes literal source, include, exclude, and preferred arrays so it does not depend on repository action state.

- [ ] **Step 2: Register and run the model test to verify RED**

Add this preload to `tests/runtime_suite.gd`:

```gdscript
preload("res://tests/input_mapping/test_input_mapping_model.gd"),
```

Run:

```text
Godot_v4.7.2-stable_win64_console.exe --headless --log-file .godot/test_input_mapping_model_red.log --path . -s res://tests/run_test_script.gd -- res://tests/input_mapping/test_input_mapping_model.gd
```

Expected: nonzero exit with a missing `input_mapping_model.gd` preload or missing method error.

- [ ] **Step 3: Implement the minimal pure model**

Use a typed enum and functions with no file I/O or scene-tree dependency:

```gdscript
class_name InputMappingModel
extends RefCounted

enum BindingSlot { KEYBOARD_PRIMARY, KEYBOARD_SECONDARY, GAMEPAD }

static func classify_events(events: Array[InputEvent]) -> Dictionary:
	var result := {
		BindingSlot.KEYBOARD_PRIMARY: [],
		BindingSlot.KEYBOARD_SECONDARY: [],
		BindingSlot.GAMEPAD: [],
		"unsupported": [],
	}
	var found_primary := false
	for event: InputEvent in events:
		if event is InputEventKey or event is InputEventMouseButton:
			var slot := BindingSlot.KEYBOARD_SECONDARY if found_primary else BindingSlot.KEYBOARD_PRIMARY
			result[slot].append(event)
			found_primary = true
		elif event is InputEventJoypadButton or event is InputEventJoypadMotion:
			result[BindingSlot.GAMEPAD].append(event)
		else:
			result["unsupported"].append(event)
	return result
```

`replace_slot_events` rebuilds one ordered array from the classified groups and places normalized replacements in Primary, Secondary, or Gamepad without touching unrelated groups. `discover_project_actions` accepts optional source/include/exclude/preferred arrays; production callers construct `source` from explicit ProjectSettings `input/*` properties.

- [ ] **Step 4: Run the focused model test to verify GREEN**

Run the same focused command. Expected: exit `0`, no failures or parser errors.

- [ ] **Step 5: Commit the model slice**

```text
git add addons/input_mapping/core/input_mapping_model.gd tests/input_mapping/test_input_mapping_model.gd tests/runtime_suite.gd
git commit -m "feat: add input mapping model"
```

### Task 2: Versioned Store and Runtime Service

**Files:**
- Create: `addons/input_mapping/core/input_mapping_store.gd`
- Create: `addons/input_mapping/runtime/input_mapping_service.gd`
- Create: `addons/input_mapping/input_mapping_plugin.gd`
- Create: `addons/input_mapping/plugin.cfg`
- Create: `tests/input_mapping/test_input_mapping_service.gd`
- Modify: `tests/runtime_suite.gd`
- Modify: `project.godot`

**Interfaces:**
- Consumes: Task 1's `InputMappingModel` methods and slot enum.
- Produces: `InputMappingStore.load_overrides(path) -> Dictionary`, `save_overrides(path, overrides) -> bool`, `clear_overrides(path) -> bool`, and the `InputMappingService` public runtime contract from the design spec.

- [ ] **Step 1: Write failing service and persistence tests**

Use uniquely named temporary Input Map actions and a unique `user://input_mapping_test_<ticks>.cfg`. Restore or erase all test actions and delete only that exact temporary file in test cleanup.

Set `service.auto_initialize = false` before adding test instances to the tree, then call `initialize(test_path, [action_name])` explicitly. The production default remains `true`, so the registered autoload initializes once from `user://input_mappings.cfg` in `_ready()`.

The test must demonstrate:

```gdscript
var service := SERVICE.new()
add_child(service)
service.initialize(test_path, [action_name])
var replacement := InputEventKey.new()
replacement.physical_keycode = KEY_Q
if not service.replace_slot(action_name, MODEL.BindingSlot.KEYBOARD_PRIMARY, replacement):
	failures.append("service rejected a compatible primary replacement")
var reloaded := SERVICE.new()
add_child(reloaded)
reloaded.initialize(test_path, [action_name])
var loaded: Array[InputEvent] = reloaded.get_slot_events(action_name, MODEL.BindingSlot.KEYBOARD_PRIMARY)
if loaded.size() != 1 or (loaded[0] as InputEventKey).physical_keycode != KEY_Q:
	failures.append("saved primary binding did not survive service reload")
```

Add separate assertions for clearing an empty/non-empty group, duplicate keys on two actions, authored-default restore after mutation, a newly added action using defaults, a removed saved action being ignored, malformed and wrong-category slot values being ignored, and two reloads not duplicating events. Confirm a save failure emits `persistence_failed` while leaving the live replacement active.

- [ ] **Step 2: Register and run the service test to verify RED**

Add:

```gdscript
preload("res://tests/input_mapping/test_input_mapping_service.gd"),
```

Run the service test through `tests/run_test_script.gd`. Expected: nonzero exit because store/service scripts do not exist.

- [ ] **Step 3: Implement the version-1 ConfigFile store**

Store the schema in `[meta] schema_version=1` and one Dictionary per action in `[actions]`. Return a structured result so the service can distinguish a normal missing file from corruption:

```gdscript
class_name InputMappingStore
extends RefCounted

const SCHEMA_VERSION := 1

func load_overrides(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": true, "missing": true, "actions": {}}
	var config := ConfigFile.new()
	var error := config.load(path)
	if error != OK:
		return {"ok": false, "missing": false, "actions": {}, "error": error}
	if int(config.get_value("meta", "schema_version", -1)) != SCHEMA_VERSION:
		return {"ok": false, "missing": false, "actions": {}, "error": ERR_INVALID_DATA}
	var actions: Dictionary = config.get_value("actions", "overrides", {})
	return {"ok": actions is Dictionary, "missing": false, "actions": actions}
```

`save_overrides` writes the complete current override Dictionary. `clear_overrides` removes only the configured file and treats a missing file as success.

- [ ] **Step 4: Implement the autoload service and editor registration**

The service captures deep-copied defaults before loading, exposes the exact typed public methods and signals from the spec, validates every loaded event by slot, rebuilds live actions through Task 1's model, and tracks only customized actions.

The editor plugin is intentionally small:

```gdscript
@tool
extends EditorPlugin

const AUTOLOAD_NAME := "InputMapping"
const AUTOLOAD_PATH := "res://addons/input_mapping/runtime/input_mapping_service.gd"

func _enter_tree() -> void:
	if not ProjectSettings.has_setting("autoload/%s" % AUTOLOAD_NAME):
		add_autoload_singleton(AUTOLOAD_NAME, AUTOLOAD_PATH)

func _exit_tree() -> void:
	if ProjectSettings.has_setting("autoload/%s" % AUTOLOAD_NAME):
		remove_autoload_singleton(AUTOLOAD_NAME)
```

Add `InputMapping="*res://addons/input_mapping/runtime/input_mapping_service.gd"` to `[autoload]` and append `res://addons/input_mapping/plugin.cfg` to the existing enabled-plugin array. Edit only those two `project.godot` hunks; preserve the user's Input Map changes.

- [ ] **Step 5: Run the focused service test and full suite**

Expected: focused test exits `0`; full runtime suite exits `0`. If the full baseline reveals an unrelated pre-existing failure, record it before proceeding and verify the focused slice independently.

- [ ] **Step 6: Commit only the service slice**

Stage the new addon/test files and `tests/runtime_suite.gd`. For `project.godot`, interactively stage only the new autoload and editor-plugin hunks; leave the user's `dash`/`interact` hunks unstaged.

```text
git commit -m "feat: persist runtime input mappings"
```

### Task 3: Reusable Four-Column Menu

**Files:**
- Create: `addons/input_mapping/ui/input_event_formatter.gd`
- Create: `addons/input_mapping/ui/input_binding_button.gd`
- Create: `addons/input_mapping/ui/input_binding_button.tscn`
- Create: `addons/input_mapping/ui/input_mapping_menu.gd`
- Create: `addons/input_mapping/ui/input_mapping_menu.tscn`
- Create: `addons/input_mapping/translations/input_mapping.csv`
- Create: `tests/input_mapping/test_input_mapping_ui.gd`
- Modify: `addons/input_mapping/runtime/input_mapping_service.gd`
- Modify: `tests/runtime_suite.gd`

**Interfaces:**
- Consumes: `InputMappingService`, `InputMappingModel.BindingSlot`, and the service's change/reset/failure signals.
- Produces: `InputBindingButton.configure(service, action, slot)`, `begin_capture()`, `cancel_capture()`, `consume_capture_event(event) -> bool`; `InputMappingMenu.bind_service(service)`, `open_menu()`, `is_capturing()`, and `back_requested`.

- [ ] **Step 1: Write failing UI behavior and scene-contract tests**

The tests load and instantiate both scenes, assert required named nodes (`Title`, `Instruction`, `HeaderGrid`, `ActionsGrid`, `EmptyLabel`, `StatusLabel`, `ResetButton`, `BackButton`), and bind a real service using test actions.

Assert that row generation yields one action label and three binding buttons per action. Drive button methods directly with real events:

```gdscript
button.begin_capture()
var release := InputEventKey.new()
release.physical_keycode = KEY_R
release.pressed = false
if button.consume_capture_event(release):
	failures.append("binding button consumed a key release")
var press := InputEventKey.new()
press.physical_keycode = KEY_R
press.pressed = true
if not button.consume_capture_event(press):
	failures.append("binding button did not consume a compatible key press")
```

Also prove gamepad capture rejects the mouse activation event, `Escape` cancels without mutation, Delete clears, one active button cancels a previous capture, missing actions show the empty-state label, and locale changes refresh labels without rebuilding the service.

- [ ] **Step 2: Register and run the UI test to verify RED**

Add its preload to `tests/runtime_suite.gd` and run it through `run_test_script.gd`. Expected: missing scene/script failure.

- [ ] **Step 3: Implement localized event formatting and capture button**

The formatter maps empty, common mouse buttons, gamepad face/shoulder/D-pad buttons, and signed axes to translation keys; keys prefer `physical_keycode` and fall back to `keycode`/`as_text()`.

The button owns only one action/slot and delegates mutation:

```gdscript
func consume_capture_event(event: InputEvent) -> bool:
	if not _capturing:
		return false
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_ESCAPE or event.keycode == KEY_ESCAPE:
			cancel_capture()
			return true
		if event.physical_keycode in [KEY_BACKSPACE, KEY_DELETE] or event.keycode in [KEY_BACKSPACE, KEY_DELETE]:
			_service.clear_slot(action, slot)
			finish_capture()
			return true
	if not MODEL.is_event_compatible(event, slot):
		return false
	_service.replace_slot(action, slot, MODEL.normalize_event(event))
	finish_capture()
	return true
```

The production `_unhandled_input` wrapper calls this method and marks the viewport handled only when it returns `true`.

- [ ] **Step 4: Implement the dynamic menu and reusable scenes**

Use a `ScrollContainer` with a four-column `GridContainer`. Build rows in project order whenever `open_menu()` runs, assign equal stretch to the three binding columns, connect hover focus, and maintain exactly one capturing button. The sticky header stays outside the scrolling content. Reset calls `restore_defaults`; Back is blocked from closing only while a button owns capture.

- [ ] **Step 5: Add and register addon translations**

Create CSV rows for title, instructions, four headers, capture prompt, empty binding, empty action list, reset, back, save failure, mouse buttons, gamepad buttons, D-pad, stick axes, and triggers. The service loads this catalog into runtime `Translation` resources during startup and removes its owned resources on teardown, using the same CSV parsing pattern as `scripts/ui/menu_localization.gd` without its current early return.

- [ ] **Step 6: Run focused UI test and full suite**

Expected: both commands exit `0`, with no parser errors, missing resources, or leaked-node warnings attributable to these tests.

- [ ] **Step 7: Commit the reusable UI slice**

```text
git add addons/input_mapping/ui addons/input_mapping/translations addons/input_mapping/runtime/input_mapping_service.gd tests/input_mapping/test_input_mapping_ui.gd tests/runtime_suite.gd
git commit -m "feat: add reusable input mapping menu"
```

### Task 4: Wellwell Settings and Bilingual Integration

**Files:**
- Modify: `scenes/ui/settings.tscn`
- Modify: `scripts/ui/settings_menu.gd`
- Modify: `localization/menu.csv`
- Modify after Godot import: `localization/menu.en.translation`
- Modify after Godot import: `localization/menu.zh_CN.translation`
- Modify: `tests/ui/test_menu_features.gd`
- Modify: `tests/ui/capture_menu.gd`

**Interfaces:**
- Consumes: addon `InputMappingMenu.open_menu()`, `back_requested`, and `InputMapping.restore_defaults()`.
- Produces: Wellwell `InputMappingButton`, embedded `InputMappingMenu`, localized action-name keys, and Settings navigation/reset behavior.

- [ ] **Step 1: Extend existing UI tests before production changes**

Add `InputMappingButton` and `InputMappingMenu` to the Settings scene contract. Add literal required translation keys:

```gdscript
"SETTINGS_INPUT_MAPPING",
"INPUT_ACTION_MOVE_LEFT",
"INPUT_ACTION_MOVE_RIGHT",
"INPUT_ACTION_MOVE_UP",
"INPUT_ACTION_MOVE_DOWN",
"INPUT_ACTION_JUMP",
"INPUT_ACTION_DASH",
"INPUT_ACTION_INTERACT",
```

Instantiate Settings with a real or narrow fake input service and assert opening hides the normal Panel, shows the addon menu, addon Back restores the Panel and button focus target, global Restore Defaults calls both managers, and `ui_cancel` does not close Settings through the parent while the addon menu is open.

- [ ] **Step 2: Run the focused menu-feature test to verify RED**

Expected: failures naming missing scene nodes, translation keys, and routing methods.

- [ ] **Step 3: Embed the addon scene and route navigation**

Add a new three-cell row to Settings' existing options grid: localized label, `InputMappingButton`, spacer. Instantiate the addon full-rect scene after the Settings panel so it draws on top and starts hidden.

Update `settings_menu.gd` with typed references and injectable lookup:

```gdscript
@onready var input_mapping_button: Button = %InputMappingButton
@onready var input_mapping_menu: Control = %InputMappingMenu

func _open_input_mapping() -> void:
	%Panel.hide()
	input_mapping_menu.call("open_menu")

func _close_input_mapping() -> void:
	input_mapping_menu.hide()
	%Panel.show()
	input_mapping_button.grab_focus.call_deferred()
```

Guard parent `ui_cancel` while the child menu is visible. Extend `_reset_defaults()` to call `/root/InputMapping.restore_defaults()` when the singleton is present.

- [ ] **Step 4: Add Wellwell English and Chinese copy**

Add the Settings entry and seven action-name rows to `localization/menu.csv` with the exact translations approved in the spec. Run one headless editor import so the tracked `.translation` artifacts reflect the CSV.

- [ ] **Step 5: Extend screenshot capture routing**

Update `tests/ui/capture_menu.gd` to open Input Mapping from Settings and save both `input_mapping.png` and `input_mapping_en.png`, restoring locale and navigation state afterward.

- [ ] **Step 6: Run focused UI tests and full suite**

Expected: focused menu tests and full suite exit `0`. Inspect output for translation-key misses and scene parser warnings.

- [ ] **Step 7: Commit the Wellwell integration**

```text
git add scenes/ui/settings.tscn scripts/ui/settings_menu.gd localization/menu.csv localization/menu.en.translation localization/menu.zh_CN.translation tests/ui/test_menu_features.gd tests/ui/capture_menu.gd
git commit -m "feat: integrate bilingual input settings"
```

### Task 5: Addon Documentation and Final Verification

**Files:**
- Create: `addons/input_mapping/README.md`
- Modify only if a real regression requires it: files already owned by Tasks 1-4 and their tests.

**Interfaces:**
- Consumes: the completed addon public API and scene paths.
- Produces: standalone installation and reuse instructions plus final verification evidence.

- [ ] **Step 1: Write the addon README**

Document:

- Copying `addons/input_mapping/` into a Godot 4 project and enabling Input Mapping under Plugins.
- The installed `InputMapping` autoload and persistence path.
- Instantiating `res://addons/input_mapping/ui/input_mapping_menu.tscn`.
- Automatic action discovery and include/exclude/preferred-order properties.
- The `INPUT_ACTION_<UPPER_SNAKE_CASE>` translation convention and fallback behavior.
- Primary, Secondary, and grouped Gamepad semantics.
- Capture, clear, cancel, duplicate-binding, restore-default, and project-update behavior.
- The public methods/signals and `en`/`zh_CN` translation scope.

- [ ] **Step 2: Run import and project parse verification**

Run Godot headless with `--editor --quit-after 2` and a repository-local log. Expected: exit `0`, no addon parser errors, missing dependencies, or invalid scene resources.

- [ ] **Step 3: Run the complete runtime suite fresh**

Run:

```text
Godot_v4.7.2-stable_win64_console.exe --headless --log-file .godot/input_mapping_final_suite.log --path . -s res://tests/run_runtime_suite.gd
```

Expected: exit `0` with the suite reporting no failures.

- [ ] **Step 4: Capture and inspect both locales**

Run `tests/ui/capture_menu.gd`, then inspect Settings and Input Mapping screenshots for both languages. Verify four aligned columns, readable grouped gamepad bindings, no clipping at 1280x720, visible focus styling, and usable action buttons.

- [ ] **Step 5: Audit the final diff and requirements**

Confirm every acceptance criterion in the spec has a corresponding test or visual check. Run `git diff --check`. Verify `git status --short` still shows the user's pre-existing `save_point.tscn` and Input Map changes rather than staging or reverting them.

- [ ] **Step 6: Commit documentation and any verified polish**

```text
git add addons/input_mapping/README.md
git commit -m "docs: document input mapping addon"
```
