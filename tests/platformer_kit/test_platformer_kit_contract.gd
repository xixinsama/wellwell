extends Node

const MANIFEST_PATH := "res://addons/platformer_kit/plugin.cfg"
const PLUGIN_SCRIPT_PATH := "res://addons/platformer_kit/platformer_kit_plugin.gd"


func run() -> Array[String]:
	var failures: Array[String] = []
	if not FileAccess.file_exists(MANIFEST_PATH):
		return ["Platformer Kit addon manifest is missing"]
	var config := ConfigFile.new()
	if config.load(MANIFEST_PATH) != OK:
		return ["Platformer Kit addon manifest could not be loaded"]
	if String(config.get_value("plugin", "name", "")) != "Platformer Kit":
		failures.append("Platformer Kit addon name is not stable")
	if String(config.get_value("plugin", "version", "")) != "0.1.0":
		failures.append("Platformer Kit addon version is not 0.1.0")
	if String(config.get_value("plugin", "script", "")) != "platformer_kit_plugin.gd":
		failures.append("Platformer Kit manifest does not use its local plugin script")
	if not ResourceLoader.exists(PLUGIN_SCRIPT_PATH, "Script"):
		failures.append("Platformer Kit editor plugin script is missing")
	else:
		var plugin_script := load(PLUGIN_SCRIPT_PATH) as Script
		if plugin_script == null or plugin_script.get_instance_base_type() != &"EditorPlugin":
			failures.append("Platformer Kit plugin script does not extend EditorPlugin")
	return failures

