class_name WellwellGlobalSettingsManager
extends Node

const SETTINGS_STORE: Script = preload("res://scripts/save/global_settings_store.gd")

const WINDOWED := "windowed"
const FULLSCREEN := "fullscreen"

var _store: RefCounted = SETTINGS_STORE.new()
var _display_mode := WINDOWED
var _master_volume := 0.7
var _music_volume := 0.7
var _sfx_volume := 0.8
var _fog_enabled := true


func _ready() -> void:
	load_settings()


func setup_store(store: RefCounted, load_immediately := true) -> void:
	_store = store
	if load_immediately:
		load_settings()


func load_settings() -> void:
	var loaded: Dictionary = _store.load_settings()
	var mode := String(loaded.get("display_mode", WINDOWED))
	_display_mode = mode if mode == WINDOWED or mode == FULLSCREEN else WINDOWED
	_master_volume = clampf(float(loaded.get("master_volume", 0.7)), 0.0, 1.0)
	_music_volume = clampf(float(loaded.get("music_volume", 0.7)), 0.0, 1.0)
	_sfx_volume = clampf(float(loaded.get("sfx_volume", 0.8)), 0.0, 1.0)
	_fog_enabled = bool(loaded.get("fog_enabled", true))
	_save()


func get_display_mode() -> String:
	return _display_mode


func get_master_volume() -> float:
	return _master_volume


func get_music_volume() -> float:
	return _music_volume


func get_sfx_volume() -> float:
	return _sfx_volume


func is_fog_enabled() -> bool:
	return _fog_enabled


func set_fog_enabled(enabled: bool) -> void:
	_fog_enabled = enabled
	_save()


func set_audio_volumes(master_volume: float, music_volume: float, sfx_volume: float) -> void:
	_master_volume = clampf(master_volume, 0.0, 1.0)
	_music_volume = clampf(music_volume, 0.0, 1.0)
	_sfx_volume = clampf(sfx_volume, 0.0, 1.0)
	_save()


func _save() -> void:
	_store.save({
		"display_mode": _display_mode,
		"master_volume": _master_volume,
		"music_volume": _music_volume,
		"sfx_volume": _sfx_volume,
		"fog_enabled": _fog_enabled,
	})
