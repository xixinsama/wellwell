extends Node

## Zoomed-in preview must not clip the terrain inside the viewport.
##
## The preview layer used to size its clip container from the world origin, so at
## high zoom the container's right/bottom edges landed inside the viewport and cut
## the terrain off along a straight line (a rectangular bite growing up and to the
## left). The container now covers the whole layer and the terrain instance carries
## the world transform.

const PREVIEW_PATH := "res://addons/world_editor/world_terrain_preview_layer.gd"
const WORLD_DATA := preload("res://addons/platformer_kit/world/data/world_data.gd")
const ROOM_DATA := preload("res://addons/platformer_kit/world/data/room_data.gd")
const WORLD_TERRAIN := "user://zoom_test_world_terrain.tscn"
const ROOM_TERRAIN := "user://zoom_test_room_terrain.tscn"
const VIEWPORT := Vector2(800.0, 600.0)
const ZOOM := 4.0


func run() -> Array[String]:
	var failures: Array[String] = []
	var script := load(PREVIEW_PATH) as Script
	if script == null:
		return ["world terrain preview layer could not be loaded"]
	var tile_set := load("res://resources/tilesets/primordial_tileset.tres") as TileSet
	if tile_set == null:
		return ["primordial tileset could not be loaded"]
	if not _make_terrain_scene(WORLD_TERRAIN, tile_set, "WorldTerrain") or not _make_terrain_scene(
		ROOM_TERRAIN, tile_set, "RoomTerrain"
	):
		return ["could not build the preview terrain fixtures"]
	_assert_world_terrain_fills_the_layer(script, failures)
	_assert_room_preview_fills_the_layer(script, failures)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(WORLD_TERRAIN))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(ROOM_TERRAIN))
	return failures


func _assert_world_terrain_fills_the_layer(script: Script, failures: Array[String]) -> void:
	var world: WorldData = WORLD_DATA.new()
	world.world_id = "zoom_test"
	world.terrain_scene_path = WORLD_TERRAIN
	var room: RoomData = ROOM_DATA.new()
	room.room_id = "room_a"
	room.room_size_chunks = Vector2i.ONE
	room.terrain_scene_path = ROOM_TERRAIN
	world.rooms.assign([room])
	world.set_room_origin_chunk("room_a", Vector2i(2, 1))

	var preview := script.new() as Control
	preview.size = VIEWPORT
	add_child(preview)
	# The origin sits up-left of the view, which is what broke the old clip rect.
	var center := Vector2(900.0, 700.0)
	preview.call("set_view_transform", center, ZOOM, VIEWPORT)
	preview.call("sync_world", world)
	var container := preview.get_node_or_null("WorldTerrain") as Control
	if container == null:
		failures.append("preview did not build the world terrain container")
		preview.free()
		return
	if container.position != Vector2.ZERO or container.size != VIEWPORT:
		failures.append(
			"world terrain clip container is not the whole layer: %s / %s"
			% [str(container.position), str(container.size)]
		)
	var instance := container.get_child(0) as Node2D
	if instance == null:
		failures.append("world terrain container has no terrain instance")
	elif not is_equal_approx(instance.scale.x, ZOOM) or not is_equal_approx(instance.scale.y, ZOOM):
		failures.append("world terrain instance is not scaled by the zoom: %s" % str(instance.scale))
	elif not instance.position.is_equal_approx((Vector2.ZERO - center) * ZOOM + VIEWPORT * 0.5):
		failures.append("world terrain instance is not placed by the view transform: %s" % str(instance.position))
	preview.free()


func _assert_room_preview_fills_the_layer(script: Script, failures: Array[String]) -> void:
	var world: WorldData = WORLD_DATA.new()
	world.world_id = "zoom_test_rooms"
	var room: RoomData = ROOM_DATA.new()
	room.room_id = "room_a"
	room.room_size_chunks = Vector2i.ONE
	room.terrain_scene_path = ROOM_TERRAIN
	world.rooms.assign([room])
	world.set_room_origin_chunk("room_a", Vector2i(2, 1))

	var preview := script.new() as Control
	preview.size = VIEWPORT
	add_child(preview)
	var center := Vector2(900.0, 700.0)
	preview.call("set_view_transform", center, ZOOM, VIEWPORT)
	preview.call("sync_world", world)
	var container := preview.get_node_or_null("room_a") as Control
	if container == null:
		failures.append("preview did not build the fallback room container")
		preview.free()
		return
	if container.position != Vector2.ZERO or container.size != VIEWPORT:
		failures.append(
			"room preview clip container is not the whole layer: %s / %s"
			% [str(container.position), str(container.size)]
		)
	var instance := container.get_child(0) as Node2D
	if instance == null:
		failures.append("room preview container has no terrain instance")
	else:
		var world_origin := Vector2(RoomGrid.get_room_cell_rect(Vector2i(2, 1), Vector2i.ONE).position * 8)
		if not instance.position.is_equal_approx((world_origin - center) * ZOOM + VIEWPORT * 0.5):
			failures.append("room preview instance is not placed by the view transform: %s" % str(instance.position))
		if not is_equal_approx(instance.scale.x, ZOOM):
			failures.append("room preview instance is not scaled by the zoom")
	preview.free()


func _make_terrain_scene(path: String, tile_set: TileSet, root_name: String) -> bool:
	var root := Node2D.new()
	root.name = root_name
	var terrain := Node2D.new()
	terrain.name = "Terrain"
	root.add_child(terrain)
	terrain.owner = root
	var layer := TileMapLayer.new()
	layer.name = "SolidTiles"
	layer.tile_set = tile_set
	terrain.add_child(layer)
	layer.owner = root
	layer.set_cell(Vector2i(0, 0), 0, Vector2i(1, 0))
	var scene := PackedScene.new()
	var pack_error := scene.pack(root)
	root.free()
	if pack_error != OK:
		return false
	return ResourceSaver.save(scene, path) == OK
