# Input Mapping Plugin Design

**Date:** 2026-09-12

**Status:** Approved for planning

## Summary

Add a reusable Godot 4 runtime input-mapping plugin under `addons/input_mapping/` and integrate its menu into Wellwell's existing settings flow. The plugin discovers the host project's custom Input Map actions, renders one row per action, lets players replace keyboard/mouse and gamepad bindings, applies changes immediately, and persists only player overrides outside `project.godot`.

The menu uses four visible columns:

1. Action name
2. Primary keyboard/mouse binding
3. Secondary keyboard/mouse binding scheme
4. Gamepad binding scheme

The three binding columns are clickable. Wellwell supplies localized action names and reuses its existing menu theme; the plugin supplies reusable English and Simplified Chinese interface text.

## Goals

- Package discovery, display, capture, mutation, persistence, reset, and reusable UI as a self-contained Godot addon.
- Automatically display the custom actions defined by the host project's Input Map.
- Preserve the project's authored mappings as the restore-default source.
- Support keyboard keys, mouse buttons, gamepad buttons, and signed gamepad axes.
- Integrate the menu into Wellwell without moving input logic into game-specific UI code.
- Support both `en` and `zh_CN` for headers, prompts, status text, and Wellwell action names.
- Preserve unrelated user work already present in `project.godot` and `addons/platformer_kit/world/entities/save_point.tscn`.

## Non-goals

- Conflict confirmation, automatic swapping, or forbidding duplicate bindings.
- Multiple player profiles or separate mappings per connected controller.
- Preset control schemes.
- Steam Input glyphs or controller-family-specific artwork.
- Cloud synchronization.
- Editing Godot's built-in UI actions unless a host project explicitly includes them.
- Writing player choices back to `project.godot`.

## Chosen Architecture

### Addon boundary

The reusable implementation lives in `addons/input_mapping/` and contains:

- A `plugin.cfg` and editor plugin entry point.
- A runtime `InputMapping` autoload service installed by the editor plugin.
- Focused model/storage code for action discovery, event classification, override application, and persistence.
- A reusable `PackedScene` containing the full-screen input-mapping menu.
- Reusable row and binding-button controls.
- An English/Simplified Chinese translation catalog for plugin-owned interface text.
- A README describing installation, public configuration, scene integration, and translation-key conventions.

The editor plugin only registers or removes the runtime autoload. It does not add a dock or edit Input Map actions. Runtime behavior remains usable and testable without editor UI.

### Host-project boundary

Wellwell remains responsible for:

- Adding the input-mapping menu as a child of the existing settings scene.
- Adding an `Input Mapping` / `按键设置` button and routing open/back navigation.
- Applying `resources/ui/menu_theme.tres` to the plugin menu through normal theme inheritance.
- Defining localized display names for Wellwell's actions in `localization/menu.csv`.
- Calling the plugin reset API when the existing global Restore Defaults button is activated.

Wellwell must not parse the plugin's persistence file or manipulate individual binding slots directly.

## Public Runtime Contract

The autoload service provides typed methods equivalent to the following contract:

```gdscript
signal mapping_changed(action: StringName)
signal mappings_reset
signal persistence_failed(message: String)

func get_actions() -> Array[StringName]
func get_slot_events(action: StringName, slot: int) -> Array[InputEvent]
func replace_slot(action: StringName, slot: int, event: InputEvent) -> bool
func clear_slot(action: StringName, slot: int) -> bool
func restore_defaults() -> bool
func reload_overrides() -> bool
```

The slot identifiers are a small enum with `KEYBOARD_PRIMARY`, `KEYBOARD_SECONDARY`, and `GAMEPAD`. The menu depends on this contract rather than storage implementation details.

The reusable menu exposes configuration for:

- Explicit included actions; an empty list means automatic discovery.
- Excluded actions.
- Preferred action order; undisclosed actions follow in project order.
- The action translation-key prefix, defaulting to `INPUT_ACTION_`.

It emits `back_requested` when the player leaves the menu.

## Action Discovery and Labels

Automatic discovery reads the project's explicit `input/*` ProjectSettings entries and keeps only actions currently present in `InputMap`. This excludes Godot's implicit built-in UI actions while still allowing a host to opt into a custom action whose name begins with `ui_`.

Actions retain project-definition order. An optional preferred order moves named actions to the front without hiding newly added actions. Inclusion and exclusion settings are validated against `InputMap`; unknown names are ignored with a warning.

For action `move_left`, the menu first requests `tr("INPUT_ACTION_MOVE_LEFT")`. If the translation result still equals the key, it falls back to a title-cased form such as `Move Left`. This lets the plugin work in an unconfigured project while allowing a host to localize semantic action names accurately.

Wellwell adds translation entries for:

- `move_left`: Move Left / 向左移动
- `move_right`: Move Right / 向右移动
- `move_up`: Move Up / 向上移动
- `move_down`: Move Down / 向下移动
- `jump`: Jump / 跳跃
- `dash`: Dash / 冲刺
- `interact`: Interact / 互动

## Slot Semantics

Each action's current `InputMap` events are classified without changing their relative order:

- The first `InputEventKey` or `InputEventMouseButton` is the primary keyboard/mouse slot.
- All remaining keyboard or mouse events form the secondary keyboard/mouse scheme.
- All `InputEventJoypadButton` and `InputEventJoypadMotion` events form the gamepad scheme.
- Other event subclasses are preserved by the service but are not displayed or edited by this version of the menu.

Grouped slots display all their events in one button, separated by `/`. Replacing a grouped slot removes all events in that group and adds the single captured replacement. Replacing the primary slot affects only its first event. Clearing a slot removes all events assigned to that slot while preserving other slots and unsupported events.

This preserves Wellwell's authored left-stick and D-pad alternatives until a player explicitly replaces or clears the gamepad scheme.

Duplicate bindings across actions are valid. The service does not remove an event from another action, display a conflict dialog, or automatically swap actions.

## Input Capture and Display

Clicking or activating a binding button puts exactly that button into capture mode. The button releases keyboard focus, shows the localized `Press an input` prompt, and asks the parent menu to route unhandled input to it.

Capture rules are:

- Primary and secondary slots accept `InputEventKey` and `InputEventMouseButton` presses.
- The gamepad slot accepts `InputEventJoypadButton` presses and `InputEventJoypadMotion` values whose absolute magnitude is at least `0.5`.
- Captured axes are normalized to `-1.0` or `1.0` so controller drift is not persisted.
- Echo key events, key releases, mouse releases, and sub-threshold axis motion are ignored.
- `Escape` cancels capture without changing the map.
- `Backspace` or `Delete` clears the active slot.
- The accepted or canceling event is marked handled so it does not also trigger menu or gameplay behavior.
- Opening a gamepad capture with the mouse cannot capture the activating click because the slot rejects incompatible event types.

Event labels use Godot's key information for printable and physical keys. The plugin supplies localized names for empty slots, common mouse buttons, common gamepad buttons, D-pad directions, and signed stick/trigger axes. Unknown supported events fall back to `InputEvent.as_text()`.

## Menu Layout and Navigation

The input-mapping scene is a full-rect overlay consistent with Wellwell's existing Settings scene. It contains:

- A localized title.
- A short localized instruction.
- A scrollable four-column grid with a sticky header and one generated row per action.
- A localized status label for persistence errors and capture guidance.
- Restore Defaults and Back buttons.

Rows are generated when the menu opens so new Input Map actions appear without scene edits. Buttons support mouse hover focus and normal Godot keyboard/controller focus traversal. When the menu opens, focus moves to the first binding button, or to Back when there are no actions. Returning restores focus to Wellwell's Input Mapping entry button.

While visible, `ui_cancel` requests Back only when no binding button is capturing. During capture, physical Escape cancels capture instead of closing the menu.

The plugin menu inherits a host theme. It provides conservative minimum sizes rather than hard-coding Wellwell's colors, fonts, or pixel-art assets.

## Persistence Model

Player mappings are stored in `user://input_mappings.cfg` using `ConfigFile` with schema version `1`. Each action record contains only the three editable slot groups and a marker showing that the action has been customized. Input events are stored as Godot Variant resources, preserving key modifiers, physical key codes, gamepad button indices, device-agnostic device value, axis index, and normalized axis direction.

Startup proceeds in this order:

1. Discover current project actions.
2. Deep-copy their current `InputMap` events as the in-memory authored-default snapshot.
3. Load and validate saved overrides.
4. Apply valid overrides to matching current actions.
5. Leave actions without valid saved overrides on their current authored defaults.

Every successful replace or clear operation updates `InputMap` first and then saves the complete current override record for that action. If saving fails, the runtime change remains active, `persistence_failed` is emitted, and the UI shows a localized non-blocking error. The next binding change retries saving.

Restore Defaults replaces every discovered action with its startup snapshot and removes all saved override sections. It then emits `mappings_reset` so every row refreshes.

## Project-update and Corruption Behavior

- A newly added action has no saved override and therefore uses its new project default.
- A removed action's stale section is ignored; it does not recreate the action.
- A renamed action behaves as one removal and one addition.
- A saved action continues using its complete player override even if that action's authored default changes in a later release.
- Unknown sections, future fields, malformed events, and events of the wrong slot category are ignored individually.
- A missing file is normal and does not create a file until the first change.
- An unreadable or invalid top-level file leaves all authored defaults active, emits one warning, and is not overwritten until the player makes a new valid change or explicitly restores defaults.
- Loading is idempotent and must not duplicate events.

## Wellwell Integration

The existing Settings options grid gains a localized Input Mapping row and entry button. Activating it hides or disables the settings content, shows the plugin overlay, and preserves the paused/menu process behavior. The plugin's Back action returns to Settings rather than the main menu.

The current Restore Defaults handler performs both operations:

1. `GlobalSettings.reset_defaults()` for display, audio, fog, shake, one-way drop, and locale.
2. `InputMapping.restore_defaults()` for player bindings.

This makes the existing button an all-settings reset while the plugin's internal reset button remains input-only.

The current uncommitted edits to `project.godot` define the intended `dash` and `interact` mappings. Integration must merge around those edits and must not rewrite the Input Map section mechanically.

## Error Handling

Public mutation calls return `false` for an unknown action, invalid slot, incompatible event, or save failure. Invalid requests do not partially modify another slot. Save failure is distinct: the requested runtime map remains applied, and the signal explains that it will not survive restart.

The UI never crashes or closes because persistence failed. It refreshes from the live `InputMap`, keeps navigation available, and clears an old error after a later successful save.

An empty action list is a supported state and displays a localized `No configurable actions` message.

## Testing Strategy

New runtime tests follow the repository's `run() -> Array[String]` convention and are preloaded by `tests/runtime_suite.gd`.

Model and service tests cover:

- Project-action discovery and stable order.
- Include, exclude, and preferred-order configuration.
- Keyboard/mouse and gamepad event classification.
- Primary replacement preserving secondary, gamepad, and unsupported events.
- Group replacement and clearing.
- Duplicate bindings across different actions.
- Signed axis normalization and threshold rejection.
- Restore from a deep-copied authored-default snapshot.
- Persistence round-trip using a temporary `user://` path.
- New, deleted, malformed, and wrong-category records.
- Idempotent reload without duplicated events.

UI and integration tests cover:

- Plugin scene and required named-node contracts.
- Dynamic row generation for Wellwell's seven current actions.
- Capture acceptance, cancel, and clear behavior through callable control methods.
- Input Mapping entry and Back routing in the existing Settings scene.
- Global and input-only reset routing.
- Required English and Simplified Chinese translation keys.

Verification consists of:

```text
godot --headless --path . -s res://tests/run_runtime_suite.gd
```

The finished UI is also captured and visually inspected in both `en` and `zh_CN`, including the ordinary Settings screen and the scrollable input-mapping screen.

## Acceptance Criteria

- Enabling the addon installs its runtime service without adding editor UI.
- Opening Settings exposes a localized Input Mapping entry.
- Opening Input Mapping produces one row for every Wellwell custom input action in project order.
- Every row has action, primary, secondary, and gamepad cells.
- Clicking a binding cell captures only compatible input and immediately updates live controls.
- Escape cancels, Backspace/Delete clears, and duplicate bindings are accepted.
- Player changes survive a restart without modifying `project.godot`.
- Restore Defaults restores the exact authored mappings captured before overrides load.
- New or removed project actions and malformed saved entries do not break startup.
- English and Simplified Chinese layouts remain readable and navigable.
- The full runtime suite exits successfully.

