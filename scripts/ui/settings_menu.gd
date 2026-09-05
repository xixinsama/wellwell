class_name SettingsMenu
extends Control

signal back_requested

@onready var language_option: OptionButton = %LanguageOption
@onready var display_mode_option: OptionButton = %DisplayModeOption
@onready var master_slider: HSlider = %MasterSlider
@onready var music_slider: HSlider = %MusicSlider
@onready var sfx_slider: HSlider = %SfxSlider
@onready var master_value: Label = %MasterValue
@onready var music_value: Label = %MusicValue
@onready var sfx_value: Label = %SfxValue
@onready var fog_toggle: CheckButton = %FogToggle
@onready var camera_shake_toggle: CheckButton = %CameraShakeToggle
@onready var one_way_drop_toggle: CheckButton = %OneWayDropToggle
@onready var reset_button: Button = %ResetButton
@onready var back_button: Button = %BackButton

var _settings: Node
var _syncing := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_settings = get_node_or_null("/root/GlobalSettings")
	language_option.item_selected.connect(_on_language_selected)
	display_mode_option.item_selected.connect(_on_display_mode_selected)
	master_slider.value_changed.connect(_on_audio_changed)
	music_slider.value_changed.connect(_on_audio_changed)
	sfx_slider.value_changed.connect(_on_audio_changed)
	fog_toggle.toggled.connect(_on_fog_toggled)
	camera_shake_toggle.toggled.connect(_on_camera_shake_toggled)
	one_way_drop_toggle.toggled.connect(_on_one_way_drop_toggled)
	reset_button.pressed.connect(_reset_defaults)
	back_button.pressed.connect(_request_back)
	for control: Control in [language_option, display_mode_option, master_slider, music_slider, sfx_slider, fog_toggle, camera_shake_toggle, one_way_drop_toggle, reset_button, back_button]:
		control.mouse_entered.connect(control.grab_focus)
	hide()

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_refresh_options()

func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		_request_back()
		get_viewport().set_input_as_handled()

func open_menu() -> void:
	show()
	_sync_from_settings()
	language_option.grab_focus.call_deferred()

func _sync_from_settings() -> void:
	if _settings == null:
		return
	_syncing = true
	_refresh_options()
	language_option.select(0 if _settings.get_locale() == "en" else 1)
	display_mode_option.select(1 if _settings.get_display_mode() == "fullscreen" else 0)
	master_slider.value = _settings.get_master_volume()
	music_slider.value = _settings.get_music_volume()
	sfx_slider.value = _settings.get_sfx_volume()
	fog_toggle.button_pressed = _settings.is_fog_enabled()
	camera_shake_toggle.button_pressed = _settings.is_camera_shake_enabled()
	one_way_drop_toggle.button_pressed = _settings.is_one_way_drop_enabled()
	_update_volume_labels()
	_syncing = false

func _refresh_options() -> void:
	var language_index := language_option.selected
	var display_index := display_mode_option.selected
	language_option.clear()
	language_option.add_item(tr("SETTINGS_LANGUAGE_ENGLISH"), 0)
	language_option.add_item(tr("SETTINGS_LANGUAGE_CHINESE"), 1)
	display_mode_option.clear()
	display_mode_option.add_item(tr("SETTINGS_WINDOWED"), 0)
	display_mode_option.add_item(tr("SETTINGS_FULLSCREEN"), 1)
	if language_index >= 0:
		language_option.select(language_index)
	if display_index >= 0:
		display_mode_option.select(display_index)

func _on_language_selected(index: int) -> void:
	if _syncing or _settings == null:
		return
	_settings.set_locale("en" if index == 0 else "zh_CN")

func _on_display_mode_selected(index: int) -> void:
	if _syncing or _settings == null:
		return
	_settings.set_display_mode("fullscreen" if index == 1 else "windowed")

func _on_audio_changed(_value: float) -> void:
	_update_volume_labels()
	if _syncing or _settings == null:
		return
	_settings.set_audio_volumes(master_slider.value, music_slider.value, sfx_slider.value)

func _on_fog_toggled(enabled: bool) -> void:
	if not _syncing and _settings != null:
		_settings.set_fog_enabled(enabled)

func _on_camera_shake_toggled(enabled: bool) -> void:
	if not _syncing and _settings != null:
		_settings.set_camera_shake_enabled(enabled)

func _on_one_way_drop_toggled(enabled: bool) -> void:
	if not _syncing and _settings != null:
		_settings.set_one_way_drop_enabled(enabled)

func _reset_defaults() -> void:
	if _settings != null:
		_settings.reset_defaults()
	_sync_from_settings()

func _update_volume_labels() -> void:
	master_value.text = "%d%%" % roundi(master_slider.value * 100.0)
	music_value.text = "%d%%" % roundi(music_slider.value * 100.0)
	sfx_value.text = "%d%%" % roundi(sfx_slider.value * 100.0)

func _request_back() -> void:
	hide()
	back_requested.emit()
