class_name TileLayerContract
extends RefCounted

const REQUIRED_LAYERS: Array[String] = [
	"BackTiles", "SolidTiles", "DetailTiles"
]

const OPTIONAL_LAYERS: Array[String] = ["GlassTiles", "VisionBlockTiles", "MarkerTiles"]

static func validate_scene(scene_path: String) -> Array[String]:
	var errors: Array[String] = []
	if not ResourceLoader.exists(scene_path, "PackedScene"):
		errors.append("missing room scene: %s" % scene_path)
		return errors
	var scene: PackedScene = load(scene_path) as PackedScene
	var root := scene.instantiate()
	for layer_name: String in REQUIRED_LAYERS:
		if root.get_node_or_null("Level/" + layer_name) == null and root.get_node_or_null(layer_name) == null:
			errors.append("missing tile layer: %s" % layer_name)
	root.free()
	return errors
