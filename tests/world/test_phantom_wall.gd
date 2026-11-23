extends Node

## A phantom wall is a TileMapLayer that looks like terrain, does not collide,
## blocks sight while it stands, and dissolves when a character touches it.

const WALL_SCENE: PackedScene = preload("res://scenes/world/phantom_wall.tscn")
const BLOCK_TILE := Vector2i(0, 0)


class FakeFog extends Node:
	var refreshes := 0

	func _ready() -> void:
		add_to_group(&"fog_of_war")

	func request_refresh() -> void:
		refreshes += 1


func run() -> Array[String]:
	var failures: Array[String] = []
	var fog := FakeFog.new()
	add_child(fog)
	var wall := WALL_SCENE.instantiate() as TileMapLayer
	wall.position = Vector2(32.0, 48.0)
	wall.set_cell(Vector2i(0, 0), 0, BLOCK_TILE)
	wall.set_cell(Vector2i(0, 1), 0, BLOCK_TILE)
	add_child(wall)
	if wall.collision_enabled:
		failures.append("phantom wall layer must not collide")
	if not bool(wall.call("is_occluding")):
		failures.append("phantom wall does not block sight before it is revealed")
	if wall.call("get_world_rect") != Rect2(32.0, 48.0, 8.0, 16.0):
		failures.append("phantom wall footprint does not follow its painted cells")
	if wall.call("get_tile_layer") != wall:
		failures.append("phantom wall did not resolve its own tile layer")
	if wall.call("get_sense") == null:
		failures.append("phantom wall did not build its contact area")
	wall.set("fade_seconds", 0.0)
	if not bool(wall.call("reveal")):
		failures.append("phantom wall refused to reveal")
	if bool(wall.call("is_occluding")):
		failures.append("revealed phantom wall still blocks sight")
	if wall.visible:
		failures.append("revealed phantom wall is still drawn")
	if fog.refreshes < 1:
		failures.append("revealing the phantom wall did not refresh the fog")
	if bool(wall.call("reveal")):
		failures.append("phantom wall revealed twice")
	wall.call("reset_component")
	if not wall.visible or not bool(wall.call("is_occluding")):
		failures.append("reset_component did not restore the phantom wall")
	wall.free()
	fog.free()
	return failures
