extends CanvasLayer
class_name CrtOverlay

## Full-screen CRT finish over every other canvas layer.
##
## Lives at the top of `main.tscn` and is switched by the `crt_enabled` video
## setting; the shader itself only needs its default tuning from the scene's
## ShaderMaterial.

const SETTINGS_PATH := NodePath("/root/GlobalSettings")


func _ready() -> void:
	var settings := get_node_or_null(SETTINGS_PATH)
	if settings != null and settings.has_signal("settings_changed"):
		settings.connect("settings_changed", _refresh)
	_refresh()


func _refresh() -> void:
	var settings := get_node_or_null(SETTINGS_PATH)
	if settings == null or not settings.has_method("get_value"):
		return
	visible = bool(settings.call("get_value", &"crt_enabled"))
