# Input Mapping Addon

Reusable Godot 4 runtime input remapping with a four-column menu, immediate `InputMap` updates, versioned persistence, and English/Simplified Chinese interface text.

## Install

1. Copy `addons/input_mapping/` into the target project.
2. Open **Project > Project Settings > Plugins** and enable **Input Mapping**.
3. The plugin registers `InputMapping` from `runtime/input_mapping_service.gd` as an autoload.
4. Instantiate `res://addons/input_mapping/ui/input_mapping_menu.tscn` under the host settings UI.

The editor plugin adds no dock and does not edit Input Map actions. Disabling the plugin removes its autoload registration.

## Open and Close the Menu

The reusable scene starts hidden. Open it from a host settings screen and listen for its back request:

```gdscript
@onready var input_mapping_menu: Control = %InputMappingMenu

func _ready() -> void:
	input_mapping_menu.back_requested.connect(_on_input_mapping_back)

func _open_input_mapping() -> void:
	input_mapping_menu.open_menu()

func _on_input_mapping_back() -> void:
	# Restore the host settings panel and focus here.
	pass
```

The scene binds `/root/InputMapping` automatically. Tests or custom hosts can inject a compatible service with `bind_service(service)`.

## Action Discovery

By default, the service reads custom `input/*` project settings in project order. Godot's implicit `ui_*` actions are excluded. A menu can opt into a particular UI action or otherwise control its rows with these exported properties:

- `included_actions`: when non-empty, show only these existing actions.
- `excluded_actions`: hide these actions.
- `preferred_action_order`: move listed actions to the front; other discovered actions follow in project order.
- `action_translation_prefix`: defaults to `INPUT_ACTION_`.

An explicitly included `ui_*` action is allowed. Unknown configured names are ignored.

## Columns and Slot Semantics

Each action row contains:

| Column | Events represented | Replacement behavior |
| --- | --- | --- |
| Action | Localized semantic name | Not editable |
| Primary | First keyboard key or mouse button | Replaces only that event |
| Secondary | Remaining keyboard keys and mouse buttons | Replaces the whole displayed group with one event |
| Gamepad | All gamepad buttons and signed axes | Replaces the whole displayed group with one event |

Grouped bindings are joined with `/`. This allows an authored gamepad scheme such as left stick plus D-pad to remain visible and active until the player intentionally replaces it. Unsupported `InputEvent` subclasses stay in `InputMap` but are not shown or edited.

Duplicate bindings across actions are valid and are never silently moved or removed.

## Capture Controls

- Activate a binding button, then press the replacement input.
- Primary and Secondary accept keyboard keys and mouse buttons.
- Gamepad accepts pressed buttons and axis motion with an absolute value of at least `0.5`.
- Axis motion is saved as direction `-1.0` or `1.0`, not its transient magnitude.
- `Escape` cancels without changing the slot.
- `Backspace` or `Delete` clears the slot.
- Incompatible events and releases are ignored.

Accepted events are marked handled so the same input does not also activate a menu or gameplay action.

## Persistence and Defaults

Player overrides are stored in `user://input_mappings.cfg` with schema version `1`. Player choices never modify `project.godot`.

At startup the service:

1. Discovers current project actions.
2. Deep-copies their authored events as the restore-default snapshot.
3. Loads saved overrides.
4. Applies valid records only to actions that still exist.

New project actions use their new defaults. Removed or renamed actions are ignored. Invalid records are ignored per slot, so one malformed event does not invalidate the rest of the file. Repeated loads rebuild from authored defaults and do not duplicate events.

`restore_defaults()` restores the startup snapshot and removes the saved override file. A persistence failure leaves the current runtime mapping active and emits `persistence_failed`; it may not survive restart.

## Public Service API

The `InputMapping` autoload exposes:

```gdscript
signal mapping_changed(action: StringName)
signal mappings_reset
signal persistence_failed(message: String)

func get_actions() -> Array[StringName]
func register_actions(actions: Array[StringName]) -> void
func get_slot_events(action: StringName, slot: int) -> Array[InputEvent]
func replace_slot(action: StringName, slot: int, event: InputEvent) -> bool
func clear_slot(action: StringName, slot: int) -> bool
func restore_defaults() -> bool
func reload_overrides() -> bool
```

Slot constants are defined by `InputMappingModel.BindingSlot`:

```gdscript
InputMappingModel.BindingSlot.KEYBOARD_PRIMARY
InputMappingModel.BindingSlot.KEYBOARD_SECONDARY
InputMappingModel.BindingSlot.GAMEPAD
```

## Localization

Plugin-owned headers, instructions, capture/status text, mouse labels, and common controller labels are provided for `en` and `zh_CN` in `translations/input_mapping.csv`. The runtime service registers this catalog, so a host does not need to add the generated translation resources to `project.godot`.

For an action named `move_left`, the menu looks up:

```text
INPUT_ACTION_MOVE_LEFT
```

Add that key to the host project's translation catalog for a semantic localized label. If no translation exists, the menu falls back to `Move Left`.

## Host-wide Reset

The menu's Restore Input Defaults button resets only input mappings. A host application's global Restore Defaults action can reset both its settings and input mappings:

```gdscript
GlobalSettings.reset_defaults()
InputMapping.restore_defaults()
```

## Verification

Wellwell exercises the addon through:

```text
godot --headless --path . -s res://tests/run_test_script.gd -- res://tests/input_mapping/test_input_mapping_model.gd
godot --headless --path . -s res://tests/run_test_script.gd -- res://tests/input_mapping/test_input_mapping_service.gd
godot --headless --path . -s res://tests/run_test_script.gd -- res://tests/input_mapping/test_input_mapping_ui.gd
```

The repository's full suite is `res://tests/run_runtime_suite.gd`.
