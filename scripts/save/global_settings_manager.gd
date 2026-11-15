class_name WellwellGlobalSettingsManager
extends Node

signal settings_changed

const SETTINGS_STORE: Script = preload("res://scripts/save/global_settings_store.gd")
const SETTINGS_CATALOG: Script = preload("res://scripts/save/settings_catalog.gd")
const SETTINGS_DEFINITION: Script = preload("res://scripts/save/settings_definition.gd")

const WINDOWED := "windowed"
const FULLSCREEN := "fullscreen"
const ENGLISH := "en"
const CHINESE := "zh_CN"

var _store: RefCounted = SETTINGS_STORE.new()
var _values: Dictionary = SETTINGS_CATALOG.default_values()


func _ready() -> void:
    load_settings()


func setup_store(store: RefCounted, load_immediately := true) -> void:
    _store = store
    if load_immediately:
        load_settings()


func load_settings() -> void:
    var loaded: Dictionary = _store.load_settings()
    for definition: SettingsDefinition in SETTINGS_CATALOG.definitions():
        if definition.kind == SETTINGS_DEFINITION.KIND_ACTION:
            continue
        var raw: Variant = loaded.get(String(definition.key), definition.default_value)
        _values[definition.key] = _normalize(definition, raw)
    _apply_runtime_settings()
    _save()


func get_value(key: StringName) -> Variant:
    if _values.has(key):
        return _values[key]
    var definition: SettingsDefinition = SETTINGS_CATALOG.find_definition(key)
    return definition.default_value if definition != null else null


func set_value(key: StringName, value: Variant) -> void:
    var definition: SettingsDefinition = SETTINGS_CATALOG.find_definition(key)
    if definition == null or definition.kind == SETTINGS_DEFINITION.KIND_ACTION:
        return
    var normalized: Variant = _normalize(definition, value)
    if _values.has(key) and _values[key] == normalized:
        return
    _values[key] = normalized
    _apply_value(key)
    _save_and_notify()


func get_display_mode() -> String:
    return String(get_value(&"display_mode"))


func set_display_mode(mode: String) -> void:
    set_value(&"display_mode", mode)


func get_locale() -> String:
    return String(get_value(&"locale"))


func set_locale(locale: String) -> void:
    set_value(&"locale", locale)


func get_master_volume() -> float:
    return float(get_value(&"master_volume"))


func get_music_volume() -> float:
    return float(get_value(&"music_volume"))


func get_sfx_volume() -> float:
    return float(get_value(&"sfx_volume"))


func is_fog_enabled() -> bool:
    return bool(get_value(&"fog_enabled"))


func set_fog_enabled(enabled: bool) -> void:
    set_value(&"fog_enabled", enabled)


func is_camera_shake_enabled() -> bool:
    return bool(get_value(&"camera_shake_enabled"))


func set_camera_shake_enabled(enabled: bool) -> void:
    set_value(&"camera_shake_enabled", enabled)


func is_one_way_drop_enabled() -> bool:
    return bool(get_value(&"one_way_drop_enabled"))


func set_one_way_drop_enabled(enabled: bool) -> void:
    set_value(&"one_way_drop_enabled", enabled)


func set_audio_volumes(master_volume: float, music_volume: float, sfx_volume: float) -> void:
    _values[&"master_volume"] = clampf(master_volume, 0.0, 1.0)
    _values[&"music_volume"] = clampf(music_volume, 0.0, 1.0)
    _values[&"sfx_volume"] = clampf(sfx_volume, 0.0, 1.0)
    _apply_audio()
    _save_and_notify()


func reset_defaults() -> void:
    var defaults: Dictionary = SETTINGS_CATALOG.default_values()
    for key: StringName in defaults:
        _values[key] = defaults[key]
    _apply_runtime_settings()
    _save_and_notify()


func _normalize(definition: SettingsDefinition, value: Variant) -> Variant:
    match definition.kind:
        SETTINGS_DEFINITION.KIND_TOGGLE:
            return bool(value)
        SETTINGS_DEFINITION.KIND_SLIDER:
            return clampf(float(value), definition.min_value, definition.max_value)
        SETTINGS_DEFINITION.KIND_OPTION:
            var text := String(value)
            for option: Dictionary in definition.options:
                if String(option["value"]) == text:
                    return text
            return definition.default_value
    return value


func _apply_runtime_settings() -> void:
    TranslationServer.set_locale(get_locale())
    _apply_display_mode()
    _apply_audio()


func _apply_value(key: StringName) -> void:
    match key:
        &"locale":
            TranslationServer.set_locale(get_locale())
        &"display_mode":
            _apply_display_mode()
        &"master_volume":
            _set_bus_volume("Master", get_master_volume())
        &"music_volume":
            _set_bus_volume("Music", get_music_volume())
        &"sfx_volume":
            _set_bus_volume("SFX", get_sfx_volume())


func _save() -> void:
    _store.save(_values.duplicate())


func _save_and_notify() -> void:
    _save()
    settings_changed.emit()


func _apply_display_mode() -> void:
    var mode := DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN if get_display_mode() == FULLSCREEN else DisplayServer.WINDOW_MODE_WINDOWED
    DisplayServer.window_set_mode(mode)


func _apply_audio() -> void:
    _set_bus_volume("Master", get_master_volume())
    _set_bus_volume("Music", get_music_volume())
    _set_bus_volume("SFX", get_sfx_volume())


func _set_bus_volume(bus_name: String, linear_value: float) -> void:
    var bus_index := AudioServer.get_bus_index(bus_name)
    if bus_index < 0:
        return
    AudioServer.set_bus_volume_db(bus_index, linear_to_db(maxf(linear_value, 0.0001)))
    AudioServer.set_bus_mute(bus_index, linear_value <= 0.0)
