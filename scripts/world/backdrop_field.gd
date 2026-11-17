extends Node2D
class_name BackdropField

## Paints the soft backdrop plate behind every room's background tilemap layer.
##
## Each baked room carries an empty `Background` container in front of `Terrain`
## (see WorldTerrainRuntime._is_valid_terrain_root). This node drops one
## 320x180 plate into it, so the plate is exactly one game frame, sits at the
## room origin and scrolls with the camera for free.
##
## The plate is its own layer: every tilemap layer is left untouched and crisp.
## `background_tilemap_alpha` exists only as an escape hatch for rooms whose
## background layer is a flat opaque fill that would hide the plate.

const BACKDROP_TEXTURE: Texture2D = preload("res://assets/images/backdrop_well.png")
const DRIFT_SHADER: Shader = preload("res://scripts/shaders/backdrop_drift.gdshader")
const PLATE_NAME := "BackdropPlate"
const ROOMS_PATH := NodePath("../TerrainRoot")

## Tint and treatment. Plate colour is deliberately pale blue so the room's gas
## veil (a warm/cool overlay) decides the final hue.
@export var backdrop_texture: Texture2D = BACKDROP_TEXTURE
@export_range(0.0, 4.0, 0.05) var blur_radius := 1.2
## Horizontal travel of one scanline, in source pixels (keep it under a pixel).
@export_range(0.0, 4.0, 0.05) var sway_amount := 0.75
## Waves per scanline: higher is denser. 0.22 is about one wave every 4 rows.
@export_range(0.02, 1.0, 0.01) var sway_frequency := 0.22
## Wave cycles per second.
@export_range(0.0, 3.0, 0.01) var sway_speed := 0.35
@export var tint := Color(0.62, 0.9, 1.0)
@export_range(0.0, 3.0, 0.01) var brightness := 2.5
@export_range(0.0, 1.5, 0.01) var vignette := 0.22
## Alpha kept by the room's background tilemap. 1 = untouched and crisp.
@export_range(0.0, 1.0, 0.01) var background_tilemap_alpha := 1.0

var _plate_material: ShaderMaterial
var _decorated_rooms: Array[Node] = []


func _ready() -> void:
	_build_materials()
	var world := get_parent()
	if world != null and world.has_signal("world_ready"):
		if not world.is_connected("world_ready", decorate_rooms):
			world.connect("world_ready", decorate_rooms)
	decorate_rooms()


## Adds a plate to every loaded room that does not have one yet. Safe to call
## repeatedly; the world session re-bakes terrain on each start.
func decorate_rooms() -> void:
	if _plate_material == null:
		_build_materials()
	var rooms := _resolve_rooms_root()
	if rooms == null:
		return
	_decorated_rooms.clear()
	for room: Node in rooms.get_children():
		if _decorate_room(room):
			_decorated_rooms.append(room)


func get_plate_for_room(room: Node) -> Sprite2D:
	if room == null:
		return null
	var background := room.get_node_or_null("Background")
	if background == null:
		return null
	return background.get_node_or_null(PLATE_NAME) as Sprite2D


func get_decorated_room_count() -> int:
	return _decorated_rooms.size()


func _mcp_state() -> Dictionary:
	return {
		"decorated_rooms": _decorated_rooms.size(),
		"room_names": _decorated_rooms.map(func(room: Node) -> String: return String(room.name)),
		"plate_texture": String(backdrop_texture.resource_path) if backdrop_texture != null else "",
		"plate_size": "%dx%d" % [backdrop_texture.get_width(), backdrop_texture.get_height()] if backdrop_texture != null else "",
		"blur_radius": blur_radius,
		"sway_amount": sway_amount,
		"sway_frequency": sway_frequency,
		"sway_speed": sway_speed,
		"background_tilemap_alpha": background_tilemap_alpha,
	}


func _decorate_room(room: Node) -> bool:
	if room == null:
		return false
	var background := room.get_node_or_null("Background")
	if background == null:
		return false
	if background.has_node(PLATE_NAME):
		_sync_plate(background.get_node(PLATE_NAME) as Sprite2D)
		_apply_background_alpha(room)
		return true
	var plate := Sprite2D.new()
	plate.name = PLATE_NAME
	plate.centered = false
	plate.position = Vector2.ZERO
	plate.z_index = -1
	plate.show_behind_parent = false
	plate.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_sync_plate(plate)
	background.add_child(plate)
	_apply_background_alpha(room)
	return true


func _sync_plate(plate: Sprite2D) -> void:
	if plate == null:
		return
	plate.texture = backdrop_texture
	plate.material = _plate_material


## Tilemap layers stay crisp by default (alpha 1). The knob only exists for a
## room whose background layer is an opaque flat fill that would hide the plate.
func _apply_background_alpha(room: Node) -> void:
	var layer := room.get_node_or_null("Terrain/BackTiles") as CanvasItem
	if layer == null:
		return
	layer.modulate = Color(1.0, 1.0, 1.0, clampf(background_tilemap_alpha, 0.0, 1.0))


func _resolve_rooms_root() -> Node:
	var rooms := get_node_or_null(ROOMS_PATH)
	if rooms != null:
		return rooms
	var parent := get_parent()
	if parent == null:
		return null
	return parent.get_node_or_null("TerrainRoot")


func _build_materials() -> void:
	_plate_material = ShaderMaterial.new()
	_plate_material.shader = DRIFT_SHADER
	_apply_parameters()


func _apply_parameters() -> void:
	if _plate_material == null:
		return
	_plate_material.set_shader_parameter("blur_radius", blur_radius)
	_plate_material.set_shader_parameter("sway_amount", sway_amount)
	_plate_material.set_shader_parameter("sway_frequency", sway_frequency)
	_plate_material.set_shader_parameter("sway_speed", sway_speed)
	_plate_material.set_shader_parameter("tint", tint)
	_plate_material.set_shader_parameter("brightness", brightness)
	_plate_material.set_shader_parameter("vignette", vignette)


## Push the exported tuning values onto the shared plate material at runtime.
func apply_parameters() -> void:
	_apply_parameters()

