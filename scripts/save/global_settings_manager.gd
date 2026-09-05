class_name WellwellGlobalSettingsManager
extends Node

signal settings_changed

const SETTINGS_STORE: Script = preload("res://scripts/save/global_settings_store.gd")

const WINDOWED := "windowed"
const FULLSCREEN := "fullscreen"
const ENGLISH := "en"
const CHINESE := "zh_CN"

var _store: RefCounted = SETTINGS_STORE.new()
var _display_mode := WINDOWED
var _master_volume := 0.7
var _music_volume := 0.7
var _sfx_volume := 0.8
var _fog_enabled := true
var _locale := CHINESE
var _camera_shake_enabled := true
var _one_way_drop_enabled := true

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
    _locale = _valid_locale(String(loaded.get("locale", CHINESE)))
    _camera_shake_enabled = bool(loaded.get("camera_shake_enabled", true))
    _one_way_drop_enabled = bool(loaded.get("one_way_drop_enabled", true))
    _apply_runtime_settings()
    _save()

func get_display_mode() -> String:
    return _display_mode

func set_display_mode(mode: String) -> void:
    _display_mode = mode if mode == FULLSCREEN else WINDOWED
    _apply_display_mode()
    _save_and_notify()

func get_locale() -> String:
    return _locale

func set_locale(locale: String) -> void:
    _locale = _valid_locale(locale)
    TranslationServer.set_locale(_locale)
    _save_and_notify()

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
    _save_and_notify()

func is_camera_shake_enabled() -> bool:
    return _camera_shake_enabled

func set_camera_shake_enabled(enabled: bool) -> void:
    _camera_shake_enabled = enabled
    _save_and_notify()

func is_one_way_drop_enabled() -> bool:
    return _one_way_drop_enabled

func set_one_way_drop_enabled(enabled: bool) -> void:
    _one_way_drop_enabled = enabled
    _save_and_notify()

func set_audio_volumes(master_volume: float, music_volume: float, sfx_volume: float) -> void:
    _master_volume = clampf(master_volume, 0.0, 1.0)
    _music_volume = clampf(music_volume, 0.0, 1.0)
    _sfx_volume = clampf(sfx_volume, 0.0, 1.0)
    _apply_audio()
    _save_and_notify()

func reset_defaults() -> void:
    _display_mode = WINDOWED
    _master_volume = 0.7
    _music_volume = 0.7
    _sfx_volume = 0.8
    _fog_enabled = true
    _locale = CHINESE
    _camera_shake_enabled = true
    _one_way_drop_enabled = true
    _apply_runtime_settings()
    _save_and_notify()

func _save() -> void:
    _store.save({
        "display_mode": _display_mode,
        "master_volume": _master_volume,
        "music_volume": _music_volume,
        "sfx_volume": _sfx_volume,
        "fog_enabled": _fog_enabled,
        "locale": _locale,
        "camera_shake_enabled": _camera_shake_enabled,
        "one_way_drop_enabled": _one_way_drop_enabled,
    })

func _save_and_notify() -> void:
    _save()
    settings_changed.emit()

func _apply_runtime_settings() -> void:
    TranslationServer.set_locale(_locale)
    _apply_display_mode()
    _apply_audio()

func _apply_display_mode() -> void:
    var mode := DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN if _display_mode == FULLSCREEN else DisplayServer.WINDOW_MODE_WINDOWED
    DisplayServer.window_set_mode(mode)

func _apply_audio() -> void:
    _set_bus_volume("Master", _master_volume)
    _set_bus_volume("Music", _music_volume)
    _set_bus_volume("SFX", _sfx_volume)

func _set_bus_volume(bus_name: String, linear_value: float) -> void:
    var bus_index := AudioServer.get_bus_index(bus_name)
    if bus_index < 0:
        return
    AudioServer.set_bus_volume_db(bus_index, linear_to_db(maxf(linear_value, 0.0001)))
    AudioServer.set_bus_mute(bus_index, linear_value <= 0.0)

func _valid_locale(locale: String) -> String:
    return ENGLISH if locale == ENGLISH else CHINESE
