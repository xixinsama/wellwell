extends Node

## Atlas (0,8) is the spike. Its alternatives rotate it, every spike cell gets a
## half-tile Killzone, and touching one returns the player to `spawn_position`.

const BUILDER_PATH := "res://scripts/world/spike_hazard_area_builder.gd"
const TILESET_PATH := "res://resources/tilesets/primordial_tileset.tres"
const TEMPLATE_PATH := "res://scenes/rooms/template/level_template.tscn"
const ROOM_PATH := "res://scenes/levels/the_world/room_01_00.tscn"
const ROOM_BAKER := preload("res://addons/world_editor/authoring/room/room_baker.gd")
const SPIKE := Vector2i(0, 8)


class FakePlayer:
	extends Node2D
	var spawn_position := Vector2(40, 56)
	var events: Array[String] = []

	func respawn_at(target: Vector2) -> void:
		global_position = target
		events.append("respawn")

	func play_hurt_effect() -> void:
		events.append("hurt:%s" % str(global_position))


func run() -> Array[String]:
	var failures: Array[String] = []
	_assert_tileset(failures)
	_assert_builder_geometry(failures)
	_assert_contact_respawns(failures)
	_assert_template_and_bake(failures)
	return failures


func _assert_tileset(failures: Array[String]) -> void:
	var tile_set := load(TILESET_PATH) as TileSet
	if tile_set == null:
		failures.append("primordial tileset could not be loaded")
		return
	var source := tile_set.get_source(0) as TileSetAtlasSource
	if source == null or not source.has_tile(SPIKE):
		failures.append("the spike tile %s is missing" % SPIKE)
		return
	if source.get_alternative_tiles_count(SPIKE) != 4:
		failures.append("the spike must have four alternatives")
		return
	var expected_flags: Array[Array] = [
		[false, false, false],
		[true, false, true],
		[true, true, false],
		[false, true, true],
	]
	for index: int in 4:
		var alternative_id := source.get_alternative_tile_id(SPIKE, index)
		if alternative_id != index:
			failures.append("spike alternative %d has id %d" % [index, alternative_id])
			continue
		var data := source.get_tile_data(SPIKE, alternative_id)
		if data == null:
			failures.append("spike alternative %d has no TileData" % index)
			continue
		var flags: Array = expected_flags[index]
		if data.flip_h != bool(flags[0]) or data.flip_v != bool(flags[1]) or data.transpose != bool(flags[2]):
			failures.append("spike alternative %d has flags %s/%s/%s" % [
				index, data.flip_h, data.flip_v, data.transpose,
			])
		if data.get_collision_polygons_count(0) != 0:
			failures.append("spike alternative %d must not have solid collision" % index)


func _assert_builder_geometry(failures: Array[String]) -> void:
	var builder := _build_spike_terrain(failures)
	if builder == null:
		return
	if builder.get_child_count() != 4:
		failures.append("expected four spike zones, found %d" % builder.get_child_count())
	var expected := {
		"SpikeZone_0_0": [Vector2(324, 6), Vector2(8, 4)],
		"SpikeZone_1_0": [Vector2(330, 4), Vector2(4, 8)],
		"SpikeZone_2_0": [Vector2(340, 2), Vector2(8, 4)],
		"SpikeZone_3_0": [Vector2(350, 4), Vector2(4, 8)],
	}
	for zone_name: String in expected:
		var zone := builder.get_node_or_null(zone_name) as Area2D
		if zone == null:
			failures.append("missing spike zone %s" % zone_name)
			continue
		var wanted: Array = expected[zone_name]
		if not zone.global_position.is_equal_approx(wanted[0]):
			failures.append("%s is at %s, expected %s" % [zone_name, zone.global_position, wanted[0]])
		var shape := zone.get_node("CollisionShape2D").shape as RectangleShape2D
		if shape == null or not shape.size.is_equal_approx(wanted[1]):
			failures.append("%s has the wrong trigger size" % zone_name)
		if zone.collision_layer != 0 or zone.collision_mask != 2:
			failures.append("%s must only detect collision layer 2" % zone_name)
	builder.get_parent().free()


func _assert_contact_respawns(failures: Array[String]) -> void:
	var builder := _build_spike_terrain(failures)
	if builder == null:
		return
	var zone := builder.get_node_or_null("SpikeZone_0_0") as Area2D
	if zone == null:
		failures.append("no spike zone to test contact")
		builder.get_parent().free()
		return
	var player := FakePlayer.new()
	player.add_to_group("player")
	add_child(player)
	zone.body_entered.emit(player)
	var expected := ["respawn", "hurt:%s" % str(player.spawn_position)]
	if player.events != expected:
		failures.append("spike must respawn before hurt, got %s" % str(player.events))
	var bystander := Node2D.new()
	add_child(bystander)
	zone.body_entered.emit(bystander)
	if player.events.size() != 2:
		failures.append("a non-player body retriggered the spike")
	player.free()
	bystander.free()
	builder.get_parent().free()


func _assert_template_and_bake(failures: Array[String]) -> void:
	if not ResourceLoader.exists(BUILDER_PATH):
		failures.append("spike hazard builder is missing")
		return
	var builder_script := load(BUILDER_PATH) as Script
	var template := load(TEMPLATE_PATH) as PackedScene
	if template == null:
		failures.append("level template could not be loaded")
		return
	var template_root := template.instantiate()
	var template_builder := template_root.get_node_or_null("RoomContent/Terrain/SpikeHazardAreaBuilder")
	if template_builder == null or template_builder.get_script() != builder_script:
		failures.append("level template has no SpikeHazardAreaBuilder")
	template_root.free()
	var room := (load(ROOM_PATH) as PackedScene).instantiate()
	if room.get_node_or_null("RoomContent/Terrain/SpikeHazardAreaBuilder") == null:
		failures.append("room_01_00 did not inherit the spike hazard builder")
	var staged: Dictionary = ROOM_BAKER.new().stage(room, ROOM_PATH)
	if not staged.get("ok", false):
		failures.append("room_01_00 could not stage: %s" % staged.get("errors", []))
	else:
		var terrain := (staged["terrain_scene"] as PackedScene).instantiate()
		var baked_builder := terrain.get_node_or_null("Terrain/SpikeHazardAreaBuilder")
		if baked_builder == null:
			failures.append("baked terrain lost the spike hazard builder")
		elif baked_builder.get_child_count() != 0:
			failures.append("runtime spike zones were serialized into baked terrain")
		terrain.free()
	room.free()


func _build_spike_terrain(failures: Array[String]) -> Node2D:
	if not ResourceLoader.exists(BUILDER_PATH):
		failures.append("spike hazard builder is missing")
		return null
	var builder_script := load(BUILDER_PATH) as Script
	var tiles := load(TILESET_PATH) as TileSet
	if tiles == null:
		failures.append("primordial tileset could not be loaded")
		return null
	var terrain := Node2D.new()
	add_child(terrain)
	terrain.position = Vector2(320, 0)
	var layer := TileMapLayer.new()
	layer.tile_set = tiles
	terrain.add_child(layer)
	for index: int in 4:
		layer.set_cell(Vector2i(index, 0), 0, SPIKE, index)
	var builder := builder_script.new() as Node2D
	terrain.add_child(builder)
	return builder
