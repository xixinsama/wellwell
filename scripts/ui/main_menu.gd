class_name MainMenu
extends Control

@export var game_root_path: NodePath = NodePath("../../SubViewportContainer/SubViewport/WorldRoot")
@onready var start_button: Button = %StartButton
@onready var settings_button: Button = %SettingsButton
@onready var quit_button: Button = %QuitButton
@onready var save_slots: Control = %SaveSlots

func _ready() -> void:
    start_button.pressed.connect(_on_start_pressed)
    settings_button.pressed.connect(_on_settings_pressed)
    quit_button.pressed.connect(_on_quit_pressed)
    save_slots.connect("slot_chosen", _on_slot_chosen)
    save_slots.hide()

func _on_start_pressed() -> void:
    save_slots.visible = true
    start_button.disabled = true

func _on_slot_chosen(slot: int) -> void:
    var manager := get_node_or_null("/root/SaveManager")
    if manager != null:
        manager.start_or_continue(slot)
    save_slots.visible = false
    visible = false
    start_button.disabled = false
    var game_root := get_node_or_null(game_root_path)
    if game_root != null:
        game_root.process_mode = Node.PROCESS_MODE_INHERIT

func _on_settings_pressed() -> void:
    var settings := get_node_or_null("../Settings")
    if settings != null:
        settings.visible = true

func _on_quit_pressed() -> void:
    get_tree().quit()
