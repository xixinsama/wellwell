class_name MainMenu
extends Control

@export var game_root_path: NodePath = NodePath("../../SubViewportContainer/SubViewport/WorldRoot")

@onready var title_group: Control = %TitleGroup
@onready var panel: Control = %Panel
@onready var start_button: Button = %StartButton
@onready var settings_button: Button = %SettingsButton
@onready var quit_button: Button = %QuitButton
@onready var save_slots: Control = %SaveSlots
@onready var version_label: Label = %VersionLabel

var _settings_menu: Control

func _ready() -> void:
    process_mode = Node.PROCESS_MODE_ALWAYS
    get_tree().paused = true
    start_button.pressed.connect(_open_save_slots)
    settings_button.pressed.connect(_open_settings)
    quit_button.pressed.connect(_quit_game)
    save_slots.connect("slot_chosen", _start_game)
    save_slots.connect("back_requested", _show_home)
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
    title_group.show()
    panel.show()
    start_button.grab_focus.call_deferred()

func _start_game(slot: int) -> void:
    var manager := get_node_or_null("/root/SaveManager")
    if manager != null:
        manager.start_or_continue(slot)
    hide()
    get_tree().paused = false
    var game_root := get_node_or_null(game_root_path)
    if game_root != null:
        game_root.process_mode = Node.PROCESS_MODE_INHERIT

func _quit_game() -> void:
    get_tree().quit()

func _refresh_translated_text() -> void:
    version_label.text = tr("MENU_VERSION").format({"version": ProjectSettings.get_setting("application/config/version", "0.1.0")})

func _notification(what: int) -> void:
    if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
        _refresh_translated_text()
