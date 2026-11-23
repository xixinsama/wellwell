extends Node

## Coverage for the World editor localization helper: zh_CN/en tables, argument
## formatting, zh* normalization and unknown-key fallback.

const LOCALIZATION := preload("res://addons/world_editor/world_editor_localization.gd")
const ZH := "zh_CN"


func run() -> Array[String]:
    var failures: Array[String] = []
    LOCALIZATION.locale_override = "zh_CN"
    _assert_equals(LOCALIZATION.t("WE_NEW_WORLD"), String(LOCALIZATION.STRINGS[ZH]["WE_NEW_WORLD"]), failures, "zh button")
    _assert_equals(LOCALIZATION.t("WE_ROOMS_COUNT", [2]), String(LOCALIZATION.STRINGS[ZH]["WE_ROOMS_COUNT"]) % [2], failures, "zh count")
    _assert_equals(LOCALIZATION.t("WE_STATUS_MSG_STALE"), String(LOCALIZATION.STRINGS[ZH]["WE_STATUS_MSG_STALE"]), failures, "zh status")
    LOCALIZATION.locale_override = "en"
    _assert_equals(LOCALIZATION.t("WE_NEW_WORLD"), "New World", failures, "en button")
    _assert_equals(LOCALIZATION.t("WE_ROOMS_COUNT", [2]), "2 rooms", failures, "en count")
    LOCALIZATION.locale_override = "zh"
    _assert_equals(LOCALIZATION.t("WE_NEW_WORLD"), String(LOCALIZATION.STRINGS[ZH]["WE_NEW_WORLD"]), failures, "zh normalization")
    LOCALIZATION.locale_override = "fr"
    _assert_equals(LOCALIZATION.t("WE_NEW_WORLD"), "New World", failures, "fallback locale")
    _assert_equals(LOCALIZATION.t("WE_MISSING_KEY"), "WE_MISSING_KEY", failures, "missing key")
    LOCALIZATION.locale_override = ""
    LOCALIZATION.reset_cache()
    return failures


func _assert_equals(actual: String, expected: String, failures: Array[String], label: String) -> void:
    if actual != expected:
        failures.append("%s: expected '%s', got '%s'" % [label, expected, actual])
