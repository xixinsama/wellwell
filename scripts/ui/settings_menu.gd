class_name SettingsMenu
extends Control

@onready var fog_toggle: CheckButton = %FogToggle
@onready var master_slider: HSlider = %MasterSlider

func _ready() -> void:
	var settings := get_node_or_null("/root/GlobalSettings")
	if settings != null:
		fog_toggle.button_pressed = settings.is_fog_enabled()
		master_slider.value = settings.get_master_volume()
	fog_toggle.toggled.connect(_on_fog_toggled)
	master_slider.value_changed.connect(_on_master_changed)

func _on_fog_toggled(value: bool) -> void:
	var settings := get_node_or_null("/root/GlobalSettings")
	if settings != null:
		settings.set_fog_enabled(value)

func _on_master_changed(value: float) -> void:
	var settings := get_node_or_null("/root/GlobalSettings")
	if settings != null:
		settings.set_audio_volumes(value, settings.get_music_volume(), settings.get_sfx_volume())

