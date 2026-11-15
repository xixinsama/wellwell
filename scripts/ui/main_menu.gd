class_name MainMenu
extends Control

@export var game_root_path: NodePath = NodePath("../../SubViewportContainer/SubViewport/WorldRoot")

@onready var title_group: Control = %TitleGroup
@onready var panel: Control = %Panel
@onready var start_button: Button = %StartButton
@onready var settings_button: Button = %SettingsButton
@onready var quit_button: Button = %QuitButton
@onready var save_slots: Control = %SaveSlots
@onready var world_select: Control = %WorldSelect
@onready var version_label: Label = %VersionLabel

var _settings_menu: Control
var _save_manager_override: Node
var _game_root_override: Node
var _pending_slot := 0

func _ready() -> void:
    process_mode = Node.PROCESS_MODE_ALWAYS
    get_tree().paused = true
    start_button.pressed.connect(_open_save_slots)
    settings_button.pressed.connect(_open_settings)
    quit_button.pressed.connect(_quit_game)
    save_slots.connect("slot_chosen", _open_world_select)
    save_slots.connect("back_requested", _show_home)
    if world_select != null:
        if world_select.has_signal("world_chosen"):
            world_select.connect("world_chosen", _on_world_chosen)
        if world_select.has_signal("back_requested"):
            world_select.connect("back_requested", _back_to_slots)
    _settings_menu = get_node_or_null("../Settings") as Control
    if _settings_menu != null:
        _settings_menu.connect("back_requested", _close_settings)
    version_label.text = tr("MENU_VERSION").format({"version": ProjectSettings.get_setting("application/config/version", "0.1.0")})
    for button: Button in [start_button, settings_button, quit_button]:
        button.mouse_entered.connect(button.grab_focus)
    _show_home()
    start_button.grab_focus.call_deferred()

func _unhandled_input(event: InputEvent) -> void:
    if event.is_action_pressed("ui_cancel") and save_slots.visible:
        _show_home()
        get_viewport().set_input_as_handled()

func _open_save_slots() -> void:
    title_group.hide()
    panel.hide()
    if world_select != null:
        world_select.hide()
    save_slots.call("show_slots")

func _open_world_select(slot: int) -> void:
    _pending_slot = slot
    if world_select == null:
        _start_game(slot)
        return
    var manager := _resolve_save_manager()
    var snapshot: RefCounted = manager.prepare_slot(slot) if manager != null else null
    var saved_world_id := String(snapshot.world_id) if snapshot != null else ""
    save_slots.hide()
    world_select.call("open_select", saved_world_id)

func _on_world_chosen(world: WorldData) -> void:
    _start_game(_pending_slot, world)

func _back_to_slots() -> void:
    if world_select != null:
        world_select.hide()
    save_slots.call("show_slots")

func _open_settings() -> void:
    if _settings_menu == null:
        return
    hide()
    _settings_menu.open_menu()

func _close_settings() -> void:
    show()
    _show_home()

func _show_home() -> void:
    save_slots.hide()
    if world_select != null:
        world_select.hide()
    title_group.show()
    panel.show()
    start_button.grab_focus.call_deferred()

func bind_start_dependencies(save_manager: Node, game_root: Node) -> void:
    _save_manager_override = save_manager
    _game_root_override = game_root

func _resolve_save_manager() -> Node:
    return _save_manager_override if is_instance_valid(_save_manager_override) else get_node_or_null("/root/SaveManager")

func _resolve_game_root() -> Node:
    return _game_root_override if is_instance_valid(_game_root_override) else get_node_or_null(game_root_path)

func _start_game(slot: int, world: WorldData = null) -> void:
    var manager := _resolve_save_manager()
    var game_root := _resolve_game_root()
    if manager == null or game_root == null or not game_root.has_method("start_selected_snapshot"):
        return
    var snapshot: RefCounted = manager.prepare_slot(slot) if manager.has_method("prepare_slot") else null
    if game_root.has_method("bind_persistence_source"):
        game_root.call("bind_persistence_source", manager)
    var started := false
    if snapshot != null:
        if world != null:
            started = bool(game_root.call("start_selected_snapshot", snapshot, world))
        else:
            started = bool(game_root.call("start_selected_snapshot", snapshot))
    if not started:
        var errors: Array[String] = game_root.call("get_last_start_errors") if game_root.has_method("get_last_start_errors") else []
        var details := "" if errors.is_empty() else errors[0]
        if world_select != null and world_select.visible:
            world_select.call("show_start_error", details)
        else:
            save_slots.call("show_start_error", details)
        return
    if not manager.has_method("activate_snapshot") or not bool(manager.call("activate_snapshot", snapshot)):
        if game_root.has_method("stop"):
            game_root.call("stop")
        if world_select != null and world_select.visible:
            world_select.call("show_start_error")
        else:
            save_slots.call("show_start_error")
        return
    _pending_slot = 0
    hide()
    if world_select != null:
        world_select.hide()
    if is_inside_tree():
        get_tree().paused = false
    game_root.process_mode = Node.PROCESS_MODE_INHERIT

func _quit_game() -> void:
    get_tree().quit()

func _refresh_translated_text() -> void:
    version_label.text = tr("MENU_VERSION").format({"version": ProjectSettings.get_setting("application/config/version", "0.1.0")})

func _notification(what: int) -> void:
    if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
        _refresh_translated_text()
