@tool
class_name PhantomWallComponent2D
extends FogOccluderComponent2D

## A wall that looks solid but can be walked through, and dissolves on contact.
##
## Paint the wall on the [TileMapLayer] this script sits on, or point
## [member tiles_path] at one. The layer must have collision disabled: the tiles
## are the room's own tileset, so the wall reads exactly like the terrain while
## the player can pass through it. While the wall stands it also blocks sight —
## the fog uses the painted cells as its footprint — so whatever is behind it
## stays dark. Touching it reveals the secret: the painting fades out, the sight
## blocker stands down, and the space behind lights up.
##
## State is runtime-only. The wall is back the next time the room loads.
##
## Authoring: instance `scenes/world/phantom_wall.tscn` under
## `RoomContent/Entities` and paint tiles on the instance root. Erase the matching
## solid tiles from `Terrain/SolidTiles`, otherwise the old collision keeps the
## player out.

signal wall_revealed()

## Empty means this node itself, which must be a [TileMapLayer].
@export var tiles_path := NodePath()
## Reveal when a character touches the wall. Off lets another system call
## [method reveal] (an ability, a switch, a cutscene).
@export var reveal_on_contact := true
@export_range(0.0, 3.0, 0.05) var fade_seconds := 0.35
## Pixels added around the footprint for the contact test.
@export var sense_margin_pixels := 2.0

var _revealed := false
var _sense: Area2D
var _fade: Tween


func _ready() -> void:
	super()
	_build_sense()


func _validate_property(property: Dictionary) -> void:
	# A wall painted on tiles has no body to read a footprint from.
	if property.get(&"name") in [&"body_path", &"size_override", &"footprint_offset"]:
		property["usage"] = PROPERTY_USAGE_NO_EDITOR


func is_revealed() -> bool:
	return _revealed


func is_occluding() -> bool:
	return not _revealed and super()


func get_tile_layer() -> TileMapLayer:
	if tiles_path != NodePath():
		return get_node_or_null(tiles_path) as TileMapLayer
	# The script may be attached to a TileMapLayer, but its own class is a Node2D,
	# so the check has to go through Node.
	var node: Node = self
	return node as TileMapLayer


func get_sense() -> Area2D:
	return _sense


## Opens the wall. Returns false when it was already revealed.
func reveal() -> bool:
	if _revealed:
		return false
	_revealed = true
	refresh()
	_fade_out()
	wall_revealed.emit()
	return true


func reset_component() -> void:
	_stop_fade()
	_revealed = false
	var art := get_tile_layer()
	if art != null:
		art.visible = true
		art.modulate.a = 1.0
	refresh()


## The painted cells, in pixels. Falls back to the host shapes when this node is
## not sitting on a tile layer.
func _world_rect() -> Rect2:
	var tiles := get_tile_layer()
	if tiles == null or tiles.tile_set == null:
		return super()
	var tile_size := Vector2(tiles.tile_set.tile_size)
	if tile_size == Vector2.ZERO:
		tile_size = Vector2(8.0, 8.0)
	var result := Rect2()
	var first := true
	for cell: Vector2i in tiles.get_used_cells():
		var center := tiles.to_global(tiles.map_to_local(cell))
		var cell_rect := Rect2(center - tile_size * 0.5, tile_size)
		result = cell_rect if first else result.merge(cell_rect)
		first = false
	return result


func _build_sense() -> void:
	if not reveal_on_contact or Engine.is_editor_hint() or not is_inside_tree():
		return
	var rect := _world_rect()
	if not rect.has_area():
		return
	_sense = Area2D.new()
	_sense.name = "PhantomSense"
	_sense.collision_layer = 0
	_sense.collision_mask = 2
	_sense.monitorable = false
	var shape_node := CollisionShape2D.new()
	var box := RectangleShape2D.new()
	box.size = rect.size + Vector2(sense_margin_pixels, sense_margin_pixels) * 2.0
	shape_node.shape = box
	shape_node.position = to_local(rect.get_center())
	_sense.add_child(shape_node)
	add_child(_sense)
	_sense.body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node) -> void:
	if _revealed or not reveal_on_contact:
		return
	if not body is CharacterBody2D:
		return
	reveal()


func _fade_out() -> void:
	var art := get_tile_layer()
	if art == null:
		return
	if fade_seconds <= 0.0 or not is_inside_tree():
		art.visible = false
		return
	_stop_fade()
	_fade = create_tween()
	_fade.tween_property(art, "modulate:a", 0.0, fade_seconds)
	_fade.tween_callback(func() -> void: art.visible = false)


func _stop_fade() -> void:
	if _fade != null and _fade.is_valid():
		_fade.kill()
	_fade = null
