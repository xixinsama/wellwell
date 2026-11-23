extends Node

## Guards the directional one-way rule: a dash crossing a one-way surface must
## travel in the direction that surface blocks. Tile one-ways always block
## downward, so they live on the dedicated `one_way` physics layer and only a
## downward dash may drop that mask bit.

const PIERCER_PATH := "res://game/player/one_way_dash_piercer.gd"
const TILESET_PATH := "res://resources/tilesets/primordial_tileset.tres"
const PLAYER_SCENE := "res://scenes/player/player.tscn"

const TILE_ONE_WAY_LAYER_MASK := 1 << 4
const WORLD_LAYER_MASK := 1 << 0
const VOID_LAYER_MASK := 1 << 3


func run() -> Array[String]:
	var failures: Array[String] = []
	if not ResourceLoader.exists(PIERCER_PATH, "Script"):
		return ["one-way dash piercer is missing"]
	_assert_project_layer(failures)
	_assert_tileset_layers(failures)
	_assert_direction_helpers(failures)
	_assert_piercer_mask_rule(failures)
	_assert_one_way_body_matching(failures)
	_assert_player_composition(failures)
	return failures


func _assert_project_layer(failures: Array[String]) -> void:
	if String(ProjectSettings.get_setting("layer_names/2d_physics/layer_5", "")) != "one_way":
		failures.append("project has no one_way physics layer on layer 5")


func _assert_tileset_layers(failures: Array[String]) -> void:
	var tile_set: TileSet = load(TILESET_PATH)
	if tile_set == null:
		failures.append("primordial tileset could not be loaded")
		return
	if tile_set.get_physics_layers_count() != 2:
		failures.append("primordial tileset does not expose a separate one-way physics layer")
		return
	if tile_set.get_physics_layer_collision_layer(1) != TILE_ONE_WAY_LAYER_MASK:
		failures.append("one-way tileset layer is not on the one_way collision layer")
	if tile_set.get_physics_layer_collision_mask(1) != 2:
		failures.append("one-way tileset layer no longer detects the player layer")
	var source := tile_set.get_source(0) as TileSetAtlasSource
	if source == null:
		failures.append("primordial tileset lost its atlas source")
		return
	var one_way_tiles: Array[Vector2i] = [
		Vector2i(0, 4), Vector2i(1, 4), Vector2i(2, 4), Vector2i(3, 4)
	]
	for atlas: Vector2i in one_way_tiles:
		var tile_data := source.get_tile_data(atlas, 0)
		if tile_data == null:
			failures.append("one-way tile %s is missing" % [atlas])
			continue
		if tile_data.get_collision_polygons_count(0) != 0:
			failures.append("one-way tile %s still collides on the solid layer" % [atlas])
		if tile_data.get_collision_polygons_count(1) != 1:
			failures.append("one-way tile %s has no polygon on the one_way layer" % [atlas])
		elif not tile_data.is_collision_polygon_one_way(1, 0):
			failures.append("one-way tile %s lost its one-way flag" % [atlas])
	var flipped := source.get_tile_data(Vector2i(1, 4), 1)
	if flipped == null or flipped.get_collision_polygons_count(1) != 1:
		failures.append("flipped one-way tile (1,4) alt 1 does not share the one_way layer")
	var solid := source.get_tile_data(Vector2i(0, 0), 0)
	if solid == null or solid.get_collision_polygons_count(0) != 1:
		failures.append("solid tile lost its world-layer collision")
	elif solid.get_collision_polygons_count(1) != 0:
		failures.append("solid tile leaked onto the one_way layer")


func _assert_direction_helpers(failures: Array[String]) -> void:
	var piercer := (load(PIERCER_PATH) as Script).new() as Node
	add_child(piercer)
	var expected := {
		Vector2(0, 240): Vector2i(0, 1),
		Vector2(0, -240): Vector2i(0, -1),
		Vector2(240, 0): Vector2i(1, 0),
		Vector2(-240, 0): Vector2i(-1, 0),
		Vector2(240, 240): Vector2i.ZERO,
		Vector2(240, -240): Vector2i.ZERO,
		Vector2.ZERO: Vector2i.ZERO,
	}
	for velocity: Vector2 in expected:
		var cardinal: Vector2i = piercer.call("cardinal_direction", velocity)
		if cardinal != expected[velocity]:
			failures.append(
				"cardinal_direction(%s) returned %s instead of %s"
				% [velocity, cardinal, expected[velocity]]
			)
	var blocking_cases := [
		[Vector2(0, 1), Vector2i(0, 1), true],
		[Vector2(0, -1), Vector2i(0, 1), false],
		[Vector2(1, 0), Vector2i(1, 0), true],
		[Vector2(-1, 0), Vector2i(-1, 0), true],
		[Vector2(1, 0), Vector2i(-1, 0), false],
		[Vector2(0.70710678, 0.70710678), Vector2i(1, 0), false],
	]
	for entry: Array in blocking_cases:
		var result: bool = piercer.call("blocks_direction", entry[0], entry[1])
		if result != entry[2]:
			failures.append(
				"blocks_direction(%s, %s) returned %s instead of %s"
				% [entry[0], entry[1], result, entry[2]]
			)
	piercer.free()


func _assert_piercer_mask_rule(failures: Array[String]) -> void:
	var piercer := (load(PIERCER_PATH) as Script).new() as Node
	add_child(piercer)
	var body := CharacterBody2D.new()
	body.collision_mask = WORLD_LAYER_MASK | VOID_LAYER_MASK
	piercer.call("configure", body)
	if body.collision_mask & TILE_ONE_WAY_LAYER_MASK == 0:
		failures.append("piercer did not opt the body into the one_way layer")
	piercer.call("update", true, Vector2(0, 240))
	if not bool(piercer.call("is_tile_layer_disabled")):
		failures.append("downward dash did not drop the one_way collision mask")
	if body.collision_mask & TILE_ONE_WAY_LAYER_MASK != 0:
		failures.append("downward dash kept colliding with tile one-way platforms")
	piercer.call("clear")
	if bool(piercer.call("is_tile_layer_disabled")):
		failures.append("piercer did not restore the one_way mask on clear")
	if body.collision_mask & TILE_ONE_WAY_LAYER_MASK == 0:
		failures.append("piercer did not restore the one_way mask bit")
	for direction: Vector2 in [Vector2(240, 0), Vector2(-240, 0), Vector2(0, -240), Vector2(240, 240)]:
		piercer.call("update", true, direction)
		if bool(piercer.call("is_tile_layer_disabled")):
			failures.append("non-downward dash %s pierced tile one-way platforms" % [direction])
		piercer.call("clear")
	piercer.call("update", true, Vector2(0, 240))
	piercer.call("update", true, Vector2(0, 240))
	if not bool(piercer.call("is_tile_layer_disabled")):
		failures.append("ongoing downward dash lost its one-way pass-through")
	piercer.call("update", false, Vector2.ZERO)
	if bool(piercer.call("is_tile_layer_disabled")):
		failures.append("finished dash did not restore the one_way mask")
	body.free()
	piercer.free()


func _assert_one_way_body_matching(failures: Array[String]) -> void:
	var piercer := (load(PIERCER_PATH) as Script).new() as Node
	add_child(piercer)
	var platform := StaticBody2D.new()
	var collision := CollisionShape2D.new()
	collision.shape = RectangleShape2D.new()
	collision.one_way_collision = true
	collision.one_way_collision_direction = Vector2(0, 1)
	platform.add_child(collision)
	add_child(platform)
	if not bool(piercer.call("_is_matching_one_way_body", platform, Vector2i(0, 1))):
		failures.append("downward dash did not match a downward-blocking one-way body")
	if bool(piercer.call("_is_matching_one_way_body", platform, Vector2i(0, -1))):
		failures.append("upward dash pierced a downward-blocking one-way body")
	if bool(piercer.call("_is_matching_one_way_body", platform, Vector2i(1, 0))):
		failures.append("sideways dash pierced a downward-blocking one-way body")
	collision.one_way_collision_direction = Vector2(1, 0)
	if not bool(piercer.call("_is_matching_one_way_body", platform, Vector2i(1, 0))):
		failures.append("rightward dash did not match a right-blocking one-way body")
	var solid := CollisionShape2D.new()
	solid.shape = RectangleShape2D.new()
	platform.add_child(solid)
	if bool(piercer.call("_is_matching_one_way_body", platform, Vector2i(1, 0))):
		failures.append("dash pierced a body that also carries a solid shape")
	platform.free()
	piercer.free()


func _assert_player_composition(failures: Array[String]) -> void:
	var packed := load(PLAYER_SCENE) as PackedScene
	if packed == null:
		failures.append("player scene could not be loaded")
		return
	var player := packed.instantiate() as CharacterBody2D
	add_child(player)
	if player.get_node_or_null("OneWayDashPiercer") == null:
		failures.append("player scene is missing its OneWayDashPiercer component")
	if int(player.collision_mask) & TILE_ONE_WAY_LAYER_MASK == 0:
		failures.append("player does not collide with the one_way layer by default")
	player.free()
