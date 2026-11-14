class_name LadderTileAreaBuilder
extends Node2D

const LADDER_ZONE := preload("res://addons/platformer_kit/world/entities/ladder_zone.tscn")

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
		for cell: Vector2i in layer.get_used_cells():
			if layer.get_cell_source_id(cell) != source_id or layer.get_cell_atlas_coords(cell) != atlas_coordinates:
				continue
			var zone := LADDER_ZONE.instantiate() as Area2D
			var rectangle := RectangleShape2D.new()
			rectangle.size = Vector2(layer.tile_set.tile_size)
			zone.get_node("CollisionShape2D").shape = rectangle
			zone.set_meta("source_cell", cell)
			add_child(zone)
			zone.global_position = global_transform.affine_inverse() * layer.to_global(layer.map_to_local(cell))
			built += 1
	return built
