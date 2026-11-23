class_name SpikeHazardAreaBuilder
extends Node2D

## Turns painted (0,8) spike cells into half-tile Killzones. The art is authored
## once; the alternatives rotate it with flip_h/flip_v/transpose. The trigger
## covers the half of the cell the spike body occupies (8x4 for floor/ceiling,
## 4x8 for walls) and never becomes solid collision.

const SPIKE_ATLAS := Vector2i(0, 8)
const SOURCE_ID := 0
const BASE_HALF_RECT := Rect2(-4.0, 0.0, 8.0, 4.0)
const KILLZONE_SCENE := preload("res://scenes/world/killzone.tscn")


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
			if layer.get_cell_source_id(cell) != SOURCE_ID:
				continue
			if layer.get_cell_atlas_coords(cell) != SPIKE_ATLAS:
				continue
			var data := layer.get_cell_tile_data(cell)
			if data == null:
				continue
			var trigger := _trigger_rect(data)
			var zone := KILLZONE_SCENE.instantiate() as Area2D
			zone.name = "SpikeZone_%d_%d" % [cell.x, cell.y]
			var rectangle := RectangleShape2D.new()
			rectangle.size = trigger.size
			(zone.get_node("CollisionShape2D") as CollisionShape2D).shape = rectangle
			add_child(zone)
			var origin := layer.map_to_local(cell)
			zone.global_position = layer.to_global(origin + trigger.get_center())
			built += 1
	return built


## Mirrors TileData.get_transformed_vertices(): transpose, then flip_h, then
## flip_v. The base spike body is the bottom half of its cell.
func _trigger_rect(data: TileData) -> Rect2:
	var points := PackedVector2Array([
		BASE_HALF_RECT.position,
		Vector2(BASE_HALF_RECT.end.x, BASE_HALF_RECT.position.y),
		BASE_HALF_RECT.end,
		Vector2(BASE_HALF_RECT.position.x, BASE_HALF_RECT.end.y),
	])
	for index: int in points.size():
		var point := points[index]
		if data.transpose:
			point = Vector2(point.y, point.x)
		if data.flip_h:
			point.x = -point.x
		if data.flip_v:
			point.y = -point.y
		points[index] = point
	var bounds := Rect2(points[0], Vector2.ZERO)
	for point: Vector2 in points:
		bounds = bounds.expand(point)
	return bounds
