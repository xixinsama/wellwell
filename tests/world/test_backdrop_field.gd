extends Node

## Contract for the room backdrop plate: one 320x180 plate per room, drawn
## inside the room's `Background` container (which precedes `Terrain`), with the
## background tilemap faded so the plate reads through it.

const BACKDROP_SCRIPT := preload("res://scripts/world/backdrop_field.gd")

const ROOM_SIZE := Vector2(320, 180)


func run() -> Array[String]:
	var failures: Array[String] = []
	var world := _build_world()
	var field := Node2D.new()
	field.name = "BackdropField"
	field.set_script(BACKDROP_SCRIPT)
	world.add_child(field)
	field.call("decorate_rooms")
	var room: Node = world.get_node("TerrainRoot/room_a")
	var background: Node2D = room.get_node("Background")
	var plate := background.get_node_or_null("BackdropPlate") as Sprite2D
	if plate == null:
		failures.append("room did not receive a backdrop plate")
		world.free()
		return failures
	_assert_plate_geometry(plate, failures)
	_assert_draw_order(room, failures)
	_assert_background_alpha(room, field, failures)
	_assert_idempotent(field, background, failures)
	world.free()
	return failures


func _assert_plate_geometry(plate: Sprite2D, failures: Array[String]) -> void:
	if plate.texture == null:
		failures.append("plate has no texture")
		return
	if Vector2(plate.texture.get_width(), plate.texture.get_height()) != ROOM_SIZE:
		failures.append("plate is not one game frame (320x180)")
	if plate.centered:
		failures.append("plate must be anchored to the room origin")
	if not plate.position.is_equal_approx(Vector2.ZERO):
		failures.append("plate is not at the room origin")
	if plate.material == null:
		failures.append("plate has no drift material")


func _assert_draw_order(room: Node, failures: Array[String]) -> void:
	var background := room.get_node_or_null("Background")
	var terrain := room.get_node_or_null("Terrain")
	if background == null or terrain == null:
		failures.append("room is missing its Background/Terrain containers")
		return
	if background.get_index() > terrain.get_index():
		failures.append("Background container no longer draws before Terrain")


func _assert_background_alpha(room: Node, field: Node, failures: Array[String]) -> void:
	var back := room.get_node_or_null("Terrain/BackTiles") as CanvasItem
	if back == null:
		failures.append("room is missing its background tilemap layer")
		return
	var want := float(field.get("background_tilemap_alpha"))
	if not is_equal_approx(want, 1.0):
		failures.append("tilemap layers must stay opaque and crisp by default")
	if not is_equal_approx(back.modulate.a, want):
		failures.append("background tilemap alpha does not follow the plate setting")


func _assert_idempotent(field: Node, background: Node, failures: Array[String]) -> void:
	field.call("decorate_rooms")
	var plates := 0
	for child: Node in background.get_children():
		if child.name == "BackdropPlate":
			plates += 1
	if plates != 1:
		failures.append("re-decorating duplicated the plate (%d)" % plates)


func _build_world() -> Node2D:
	var world := Node2D.new()
	world.name = "World"
	var rooms := Node2D.new()
	rooms.name = "TerrainRoot"
	world.add_child(rooms)
	var room := Node2D.new()
	room.name = "room_a"
	rooms.add_child(room)
	var background := Node2D.new()
	background.name = "Background"
	room.add_child(background)
	var terrain := Node2D.new()
	terrain.name = "Terrain"
	room.add_child(terrain)
	var back := TileMapLayer.new()
	back.name = "BackTiles"
	terrain.add_child(back)
	return world
