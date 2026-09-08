extends Node

const SNAPSHOT_PATH := "res://addons/platformer_kit/save/save_snapshot.gd"
const CODEC_PATH := "res://addons/platformer_kit/save/save_codec.gd"
const MANAGER_PATH := "res://addons/platformer_kit/save/save_manager.gd"
const SAVEABLE_PATH := "res://addons/platformer_kit/save/saveable.gd"
const PERSISTENT_ID_PATH := "res://addons/platformer_kit/save/persistent_id.gd"


func run() -> Array[String]:
	var failures: Array[String] = []
	var scripts: Dictionary[String, Script] = {}
	for path: String in [SNAPSHOT_PATH, CODEC_PATH, MANAGER_PATH, SAVEABLE_PATH, PERSISTENT_ID_PATH]:
		var script := load(path) as Script
		if script == null or not script.can_instantiate():
			failures.append("framework save contract could not be loaded: %s" % path)
		else:
			scripts[path] = script
	if not failures.is_empty():
		return failures

	var persistent_id: Resource = scripts[PERSISTENT_ID_PATH].new()
	persistent_id.value = &"chest:forest:001"
	if not persistent_id.is_valid():
		failures.append("PersistentId rejected a stable namespaced ID")
	persistent_id.value = &"temporary id"
	if persistent_id.is_valid():
		failures.append("PersistentId accepted whitespace")

	var snapshot: RefCounted = scripts[SNAPSHOT_PATH].new()
	snapshot.slot = 1
	snapshot.world_id = "standalone"
	snapshot.set_entity_state("chest:forest:001", {"opened": true})
	var codec: RefCounted = scripts[CODEC_PATH].new()
	var decoded: RefCounted = codec.decode(codec.encode(snapshot), 1)
	if decoded == null or not bool(decoded.get_entity_state("chest:forest:001").get("opened", false)):
		failures.append("framework save codec did not round-trip stable-ID state")

	var manager: Node = scripts[MANAGER_PATH].new()
	if not manager.has_method("setup_storage"):
		failures.append("framework SaveManager does not support explicit storage injection")
	manager.free()
	return failures
