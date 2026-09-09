extends Node

const FRAMEWORK_MANIFEST := "res://addons/platformer_kit/plugin.cfg"
const FRAMEWORK_README := "res://addons/platformer_kit/README.md"
const CHANGELOG := "res://CHANGELOG.md"
const MIGRATION_GUIDE := "res://MIGRATION.md"
const RELEASE_VERSION := "0.1.0"
const LAB_SCENES: Array[String] = [
	"res://examples/movement_lab/movement_lab.tscn",
	"res://examples/movement_lab/movement_lab_debug.tscn",
	"res://examples/ability_lab/ability_lab.tscn",
	"res://examples/combat_lab/combat_lab.tscn",
	"res://examples/metroidvania_demo/metroidvania_demo.tscn",
]


func run() -> Array[String]:
	var failures: Array[String] = []
	var manifest := ConfigFile.new()
	if manifest.load(FRAMEWORK_MANIFEST) != OK:
		failures.append("Platformer Kit manifest cannot be loaded")
	else:
		var addon_version := String(manifest.get_value("plugin", "version", ""))
		if addon_version != RELEASE_VERSION:
			failures.append("Platformer Kit manifest version must be %s" % RELEASE_VERSION)
	var project_version := String(ProjectSettings.get_setting("application/config/version", ""))
	if project_version != RELEASE_VERSION:
		failures.append("project metadata version must match Platformer Kit %s" % RELEASE_VERSION)

	var framework_readme := _require_document(FRAMEWORK_README, failures)
	var changelog := _require_document(CHANGELOG, failures)
	var migration := _require_document(MIGRATION_GUIDE, failures)
	if not framework_readme.is_empty():
		for required_text: String in [
			"Platformer Kit 0.1.0",
			"## Dependency Rules",
			"## Public API",
			"## Signals",
			"## Example Labs",
			"Game Content",
			"Optional Addons",
			"Platformer Kit",
		]:
			if not framework_readme.contains(required_text):
				failures.append("framework README is missing: %s" % required_text)
		for scene_path: String in LAB_SCENES:
			if not framework_readme.contains("godot --path . %s" % scene_path):
				failures.append("framework README is missing lab command: %s" % scene_path)
	if not changelog.is_empty() and not changelog.contains("## [0.1.0]"):
		failures.append("changelog is missing the 0.1.0 release")
	if not migration.is_empty():
		for required_text: String in [
			"scripts/authoring/",
			"addons/world_editor/authoring/",
			"scripts/world/fog/",
			"addons/metroidvania_kit/map/discovery/",
			"addons/wellwell_world_editor/",
			"addons/world_editor/",
		]:
			if not migration.contains(required_text):
				failures.append("migration guide is missing path mapping: %s" % required_text)
	return failures


func _require_document(path: String, failures: Array[String]) -> String:
	if not FileAccess.file_exists(path):
		failures.append("required framework document is missing: %s" % path)
		return ""
	var source := FileAccess.get_file_as_string(path)
	if source.strip_edges().is_empty():
		failures.append("required framework document is empty: %s" % path)
	return source
