class_name LadderTileAreaBuilder
extends Node2D

const LADDER_ZONE := preload("res://addons/platformer_kit/world/entities/ladder_zone.tscn")
const CELL_RECT_MERGER := preload("res://scripts/util/cell_rect_merger.gd")

@export var source_id := 0
@export var atlas_coordinates := Vector2i(0, 7)


func _ready() -> void:
	rebuild()


func rebuild() -> int:
	for child: Node in get_children():
		child.free()
	var built := 0
	var terrain := get_parent()
	if terrain == null:
		return built
	for candidate: Node in terrain.get_children():
		var layer := candidate as TileMapLayer
		if layer == null or layer.tile_set == null:
			continue
		var cells: Array[Vector2i] = []
		for cell: Vector2i in layer.get_used_cells():
			if layer.get_cell_source_id(cell) != source_id:
				continue
			if layer.get_cell_atlas_coords(cell) != atlas_coordinates:
				continue
			cells.append(cell)
		var tile_size := Vector2(layer.tile_set.tile_size)
		for rect: Rect2i in CELL_RECT_MERGER.merge(cells):
			var zone := LADDER_ZONE.instantiate() as Area2D
			zone.name = "LadderZone_%d_%d" % [rect.position.x, rect.position.y]
			var rectangle := RectangleShape2D.new()
			rectangle.size = Vector2(rect.size) * tile_size
			zone.get_node("CollisionShape2D").shape = rectangle
			zone.set_meta("source_rect", rect)
			add_child(zone)
			var center := layer.map_to_local(rect.position)
			center += Vector2(rect.size - Vector2i.ONE) * 0.5 * tile_size
			zone.global_position = layer.to_global(center)
			built += 1
	return built
