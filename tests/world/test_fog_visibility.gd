extends Node

const FOG_VISIBILITY: Script = preload("res://addons/metroidvania_kit/map/discovery/fog_visibility.gd")
const FOG_OF_WAR: Script = preload("res://addons/metroidvania_kit/map/discovery/fog_of_war.gd")
const FOG_ZONE: Script = preload("res://scripts/world/fog_zone.gd")
const ROOM_DATA: Script = preload("res://addons/platformer_kit/world/data/room_data.gd")

const SOLID_TILE := Vector2i(0, 0)
const ONE_WAY_TILE := Vector2i(1, 0)
const PLAIN_TILE := Vector2i(2, 0)
const GLASS_TILE := Vector2i(0, 3)
const CRUMBLE_SOLID_TILE := Vector2i(3, 0)
const CRUMBLE_ONE_WAY_TILE := Vector2i(3, 4)
const DARK_MODE := 0
const LIGHT_MODE := 1
const LAYER_NAMES: Array[String] = ["BackTiles", "SolidTiles", "DetailTiles"]


class PersistenceSource extends Node:
	var explored_cells: Array[String] = []
	var explored_chunks: Array[String] = []
	var revealed_zones: Array[String] = []

	func mark_cell_explored(cell_id: String) -> bool:
		if explored_cells.has(cell_id):
			return false
		explored_cells.append(cell_id)
		return true

	func mark_chunk_explored(chunk_id: String) -> bool:
		if explored_chunks.has(chunk_id):
			return false
		explored_chunks.append(chunk_id)
		return true

	func mark_zone_revealed(zone_id: String) -> bool:
		if revealed_zones.has(zone_id):
			return false
		revealed_zones.append(zone_id)
		return true

	func get_explored_cells() -> Array[String]:
		return explored_cells.duplicate()

	func get_revealed_zones() -> Array[String]:
		return revealed_zones.duplicate()


class SettingsSource extends Node:
	var one_way_occludes := true

	func is_fog_enabled() -> bool:
		return true

	func is_one_way_occlusion_enabled() -> bool:
		return one_way_occludes


class FakeOccluder extends Node2D:
	var occluding := true
	var size_cells := Vector2i(1, 1)

	func _ready() -> void:
		add_to_group(&"fog_occluder")

	func is_occluding() -> bool:
		return occluding

	func get_world_rect() -> Rect2:
		return Rect2(global_position, Vector2(size_cells) * 8)


class FakeCellOccluder extends Node2D:
	var occluding := true
	var cells: Array[Vector2i] = []
	var one_way_cells: Array[Vector2i] = []

	func _ready() -> void:
		add_to_group(&"fog_occluder")

	func is_occluding() -> bool:
		return occluding

	func get_occluder_cells() -> Array[Vector2i]:
		return cells

	func get_occluder_one_way_cells() -> Array[Vector2i]:
		return one_way_cells


func run() -> Array[String]:
	var failures: Array[String] = []
	_assert_blocker_is_visible_but_stops_spread(failures)
	_assert_diagonal_gap_is_see_through(failures)
	_assert_one_way_blocks_downward_sight(failures)
	_assert_one_way_setting_can_disable(failures)
	_assert_room_chunks_configure_cell_bounds(failures)
	_assert_cell_ids_are_stable(failures)
	_assert_persistence_requires_explicit_binding(failures)
	_assert_blocker_classification(failures)
	_assert_erased_crumble_opens_sight(failures)
	_assert_light_zone_lights_sealed_cells(failures)
	_assert_dark_zone_stays_black_until_entered(failures)
	_assert_restore_and_focus(failures)
	_assert_partial_overlap_lights_both_sides(failures)
	_assert_sub_cell_zone_edge_refreshes(failures)
	_assert_door_occludes_sight(failures)
	_assert_cell_occluder_participates(failures)
	_assert_room_switch_clears_state(failures)
	_assert_mask_matches_lit_cells(failures)
	_assert_mask_reveal_wave_animates(failures)
	_assert_mask_quad_follows_room(failures)
	_assert_saved_exploration_updates_mask(failures)
	_assert_zone_fade_is_gradual(failures)
	_assert_focus_spotlight_reaches_the_shader(failures)
	_assert_edge_is_one_sided_and_bilinear(failures)
	_assert_hero_recess_tracks_the_body(failures)
	return failures


## The border's three rules, which are shader-only and cannot be run headless, so
## they are checked as a contract on the source:
##
##   * the creep into the revealed side is ONE-SIGNED (`tendril * (0.55 + 0.45 * n)`
##     with n in 0..1). The old form `(lobes - 0.5) * 2 * tendril` pushed the cut in
##     and out, so the fringe vanished in the low lobes and left detached patches;
##   * the per-cell opacity is read bilinearly (`cell_sample`), not with the nearest
##     `centre.a`, because one texel per cell painted every fading cell as a hard
##     8 px square;
##   * the recession is the hero term plus the light term, clamped; the light alone
##     could only move the border where the lantern lights a surface, so walls and
##     ceilings never receded.
func _assert_edge_is_one_sided_and_bilinear(failures: Array[String]) -> void:
	var path := "res://addons/metroidvania_kit/map/discovery/fog_mask.gdshader"
	if not FileAccess.file_exists(path):
		failures.append("fog mask shader is missing: %s" % path)
		return
	var source := FileAccess.get_file_as_string(path)
	for marker: String in [
		"tendril_pixels * (0.55 + 0.45 * clamp(lobes, 0.0, 1.0))",
		"vec4 cell_sample(vec2 cell_pos)",
		"float body_sharp = smoothstep(0.30, 0.70, body);",
		"float value = band * mix(1.0, body_sharp, fog_side);",
		"push += hero_push_px * (",
		"push = min(push, max_push_px);",
		"float breath01 = 0.5 + 0.5 * sin(t * breath_speed * TAU + breath_phase);",
		"float surge01 = (surge_coarse + 0.45 * surge_fine) / 1.45;",
		"fringe += breath01 * breath_pixels;",
		"fringe += surge01 * surge_pixels;",
	]:
		if not source.contains(marker):
			failures.append("fog border math is missing `%s`; see the comment above" % marker)
	if source.contains("(lobes - 0.5) * 2.0 * tendril_pixels"):
		failures.append("the creep is two-signed again, so it can drop below zero and detach")
	if source.contains("max(centre.a, tongue"):
		failures.append("the fog opacity is back to the nearest per-cell read (8 px squares)")


## The recess centre is the hero body in mask pixels, and it is pushed every frame:
## the border has to lean away from the hero on every side, which only works if the
## shader knows where the hero is.
func _assert_hero_recess_tracks_the_body(failures: Array[String]) -> void:
	var root := Node2D.new()
	var player := Node2D.new()
	player.position = Vector2(64.0, 40.0)
	root.add_child(player)
	var terrain := _make_terrain({})
	root.add_child(terrain)
	var fog: Node2D = FOG_OF_WAR.new() as Node2D
	fog.cell_size = Vector2i(8, 8)
	fog.chunk_size_pixels = Vector2i(320, 180)
	fog.call("bind_player", player)
	root.add_child(fog)
	add_child(root)
	var room: Resource = _make_room("recess_room", Vector2i.ZERO, Vector2i(1, 1))
	fog.call("bind_room", room, terrain, Vector2i.ZERO)
	fog.call("reveal_from_player")
	fog.call("_update_mask_image")
	fog.call("_process", 0.016)
	var quad := fog.get_node_or_null("FogMask") as Sprite2D
	if quad == null or not (quad.material is ShaderMaterial):
		failures.append("fog mask material missing, the recess cannot reach the shader")
		root.free()
		return
	var material := quad.material as ShaderMaterial
	var centre: Variant = material.get_shader_parameter("hero_center_px")
	var body_rect: Rect2 = fog.get("hero_body_rect")
	var mask_origin: Vector2i = fog.call("get_mask_origin_pixels")
	var expected: Vector2 = player.position + body_rect.get_center() - Vector2(mask_origin)
	if not (centre is Vector2) or not (centre as Vector2).is_equal_approx(expected):
		failures.append("hero recess centre is %s, expected the hero body at %s"
			% [str(centre), str(expected)])
	for property: String in ["hero_push_px", "hero_push_radius_px"]:
		if float(fog.get(property)) <= 0.0:
			failures.append("%s is %s, so the recess has no effect" % [property, str(fog.get(property))])
	# The creep is bounded and the recess is bounded: a fog that can move 20 px per
	# frame reads as a whole row of it disappearing.
	if float(fog.get("tendril_pixels")) > 6.0:
		failures.append("tendril_pixels is %.1f, more than the 3..4 px creep the border wants"
			% float(fog.tendril_pixels))
	if float(fog.get("light_push_px")) > 6.0:
		failures.append("light_push_px is %.1f, which alone outruns the hero recess"
			% float(fog.get("light_push_px")))
	root.free()


func _assert_blocker_is_visible_but_stops_spread(failures: Array[String]) -> void:
	var blockers: Dictionary[Vector2i, bool] = {Vector2i(1, 0): true}
	var visibility: RefCounted = FOG_VISIBILITY.new()
	var visible: Dictionary[Vector2i, bool] = visibility.compute_visible_cells(
		Vector2i(0, 0),
		Rect2i(0, 0, 4, 1),
		blockers
	)
	if not visible.has(Vector2i(1, 0)):
		failures.append("blocking cell face was not revealed")
	if visible.has(Vector2i(2, 0)):
		failures.append("fog spread propagated through a blocking cell")


func _assert_diagonal_gap_is_see_through(failures: Array[String]) -> void:
	var blockers: Dictionary[Vector2i, bool] = {
		Vector2i(2, 1): true,
		Vector2i(1, 2): true,
	}
	var visibility: RefCounted = FOG_VISIBILITY.new()
	var visible: Dictionary[Vector2i, bool] = visibility.compute_visible_cells(
		Vector2i(0, 0),
		Rect2i(0, 0, 5, 5),
		blockers
	)
	if not visible.has(Vector2i(2, 2)):
		failures.append("sight did not pass through a one-cell diagonal crack")


func _assert_one_way_blocks_downward_sight(failures: Array[String]) -> void:
	var one_way: Dictionary[Vector2i, bool] = {}
	for x in range(3):
		one_way[Vector2i(x, 2)] = true
	var visibility: RefCounted = FOG_VISIBILITY.new()
	var visible: Dictionary[Vector2i, bool] = visibility.compute_visible_cells(
		Vector2i(1, 0),
		Rect2i(0, 0, 3, 6),
		{},
		one_way
	)
	if not visible.has(Vector2i(1, 2)):
		failures.append("one-way platform cell itself was not visible")
	if visible.has(Vector2i(1, 3)):
		failures.append("sight passed downwards through a one-way platform")
	var without: Dictionary[Vector2i, bool] = visibility.compute_visible_cells(
		Vector2i(1, 0),
		Rect2i(0, 0, 3, 6),
		{},
		{}
	)
	if not without.has(Vector2i(1, 3)):
		failures.append("one-way platform blocked sight when the feature is disabled")


func _assert_one_way_setting_can_disable(failures: Array[String]) -> void:
	var root := Node2D.new()
	var player := Node2D.new()
	player.position = Vector2(164.0, 4.0)
	root.add_child(player)
	var cells: Dictionary[Vector2i, Vector2i] = {}
	for x in range(40):
		cells[Vector2i(x, 2)] = ONE_WAY_TILE
	var terrain := _make_terrain(cells)
	root.add_child(terrain)
	var settings := SettingsSource.new()
	settings.one_way_occludes = true
	root.add_child(settings)
	var fog: Node2D = FOG_OF_WAR.new() as Node2D
	fog.cell_size = Vector2i(8, 8)
	fog.chunk_size_pixels = Vector2i(320, 180)
	fog.call("bind_player", player)
	fog.call("bind_settings_source", settings)
	root.add_child(fog)
	add_child(root)
	var room: Resource = _make_room("one_way_setting", Vector2i.ZERO)
	fog.call("bind_room", room, terrain, Vector2i.ZERO)
	if fog.currently_visible.has(Vector2i(20, 3)):
		failures.append("fog ignored the one-way occlusion setting")
	settings.one_way_occludes = false
	fog.call("request_refresh")
	fog.call("reveal_from_player")
	if not fog.currently_visible.has(Vector2i(20, 3)):
		failures.append("disabling one-way occlusion did not open sight")
	root.free()


func _assert_room_chunks_configure_cell_bounds(failures: Array[String]) -> void:
	var fog: Node2D = FOG_OF_WAR.new() as Node2D
	fog.cell_size = Vector2i(8, 8)
	fog.chunk_size_pixels = Vector2i(320, 180)
	fog.set_room_chunks(Vector2i(2, 1), Vector2i(3, 2))
	if fog.map_origin_cell != Vector2i(80, 23):
		failures.append("room chunk origin did not convert to fog cells")
	if fog.map_size_cells != Vector2i(120, 45):
		failures.append("room chunk size did not use the exact total pixel extent")
	fog.free()


func _assert_cell_ids_are_stable(failures: Array[String]) -> void:
	var fog: Node2D = FOG_OF_WAR.new() as Node2D
	fog.level_id = "level_01"
	if fog.cell_to_id(Vector2i(12, -4)) != "level_01:12,-4":
		failures.append("fog cell id format changed")
	var saved_ids: Array[String] = ["level_01:12,-4", "other:1,1", "broken"]
	fog.load_explored_cells(saved_ids)
	if not fog.is_cell_explored(Vector2i(12, -4)):
		failures.append("saved fog cell id was not loaded")
	if fog.is_cell_explored(Vector2i(1, 1)):
		failures.append("foreign level cell id was loaded")
	fog.free()


func _assert_persistence_requires_explicit_binding(failures: Array[String]) -> void:
	var root := Node2D.new()
	var player := Node2D.new()
	player.position = Vector2(6.0, 10.0)
	root.add_child(player)
	var terrain := _make_terrain({Vector2i(0, 0): SOLID_TILE})
	root.add_child(terrain)
	var fog: Node2D = FOG_OF_WAR.new() as Node2D
	fog.cell_size = Vector2i(8, 8)
	fog.chunk_size_pixels = Vector2i(320, 180)
	fog.player_path = NodePath()
	fog.call("bind_player", player)
	root.add_child(fog)
	add_child(root)
	var source := PersistenceSource.new()
	root.add_child(source)
	fog.bind_persistence_source(source)
	var room: Resource = _make_room("preview", Vector2i.ZERO, Vector2i(1, 1))
	fog.call("bind_room", room, terrain, Vector2i.ZERO)
	if source.explored_cells.is_empty():
		failures.append("bound fog persistence source did not receive exploration")
	fog.bind_persistence_source(null)
	fog.call("reveal_from_player")
	root.free()


func _assert_blocker_classification(failures: Array[String]) -> void:
	var terrain := _make_terrain({
		Vector2i(1, 0): SOLID_TILE,
		Vector2i(2, 0): ONE_WAY_TILE,
		Vector2i(3, 0): GLASS_TILE,
		Vector2i(4, 0): CRUMBLE_SOLID_TILE,
		Vector2i(5, 0): CRUMBLE_ONE_WAY_TILE,
		Vector2i(6, 0): PLAIN_TILE,
	})
	var fog: Node2D = FOG_OF_WAR.new() as Node2D
	fog.cell_size = Vector2i(8, 8)
	fog.chunk_size_pixels = Vector2i(320, 180)
	var room: Resource = _make_room("classification", Vector2i.ZERO, Vector2i(1, 1))
	fog.call("bind_room", room, terrain, Vector2i.ZERO)
	var blockers: Dictionary = fog.call("_collect_sight")
	var one_way: Dictionary = fog.get("_one_way_cells")
	for cell: Vector2i in [Vector2i(1, 0), Vector2i(4, 0)]:
		if not blockers.has(cell):
			failures.append("expected sight blocker missing at %s" % cell)
	for cell: Vector2i in [Vector2i(2, 0), Vector2i(5, 0)]:
		if not one_way.has(cell):
			failures.append("one-way cell %s was not classified" % cell)
	for cell: Vector2i in [Vector2i(3, 0), Vector2i(6, 0)]:
		if blockers.has(cell) or one_way.has(cell):
			failures.append("transparent cell %s was treated as an occluder" % cell)
	fog.free()
	terrain.free()


func _assert_erased_crumble_opens_sight(failures: Array[String]) -> void:
	var terrain := _make_terrain({Vector2i(2, 0): CRUMBLE_SOLID_TILE})
	var fog: Node2D = FOG_OF_WAR.new() as Node2D
	fog.cell_size = Vector2i(8, 8)
	fog.chunk_size_pixels = Vector2i(320, 180)
	var room: Resource = _make_room("crumble_sight", Vector2i.ZERO, Vector2i(1, 1))
	fog.call("bind_room", room, terrain, Vector2i.ZERO)
	var crumble := terrain.get_node("Terrain/SolidTiles") as TileMapLayer
	var before: Dictionary = fog.call("_collect_sight")
	if not before.has(Vector2i(2, 0)):
		failures.append("crumble tile did not block sight before collapsing")
	crumble.erase_cell(Vector2i(2, 0))
	fog.call("request_refresh")
	var after: Dictionary = fog.call("_collect_sight")
	if after.has(Vector2i(2, 0)):
		failures.append("collapsed crumble tile kept blocking sight")
	fog.free()
	terrain.free()


func _assert_light_zone_lights_sealed_cells(failures: Array[String]) -> void:
	var root := Node2D.new()
	var player := Node2D.new()
	player.position = Vector2(4.0, 12.0)
	root.add_child(player)
	var solid_cells: Dictionary[Vector2i, Vector2i] = {}
	for x in range(2, 6):
		solid_cells[Vector2i(x, 0)] = SOLID_TILE
		solid_cells[Vector2i(x, 3)] = SOLID_TILE
	for y in range(1, 3):
		solid_cells[Vector2i(2, y)] = SOLID_TILE
		solid_cells[Vector2i(5, y)] = SOLID_TILE
	var terrain := _make_terrain(solid_cells)
	root.add_child(terrain)
	var zone := _make_zone(root, LIGHT_MODE, Vector2i(3, 1), Vector2i(1, 1), "light_pocket")
	var fog: Node2D = FOG_OF_WAR.new() as Node2D
	fog.cell_size = Vector2i(8, 8)
	fog.chunk_size_pixels = Vector2i(320, 180)
	fog.call("bind_player", player)
	root.add_child(fog)
	add_child(root)
	var room: Resource = _make_room("light_room", Vector2i.ZERO, Vector2i(1, 1))
	fog.call("bind_room", room, terrain, Vector2i.ZERO)
	if not fog.is_cell_lit(Vector2i(3, 1)):
		failures.append("light zone did not light a sealed cell")
	if not fog.is_cell_explored(Vector2i(3, 1)):
		failures.append("light zone cell was not recorded as explored")
	zone.free()
	root.free()


func _assert_dark_zone_stays_black_until_entered(failures: Array[String]) -> void:
	var root := Node2D.new()
	var player := Node2D.new()
	player.position = Vector2(52.0, 12.0)
	root.add_child(player)
	var terrain := _make_terrain({})
	root.add_child(terrain)
	var zone := _make_zone(root, DARK_MODE, Vector2i(1, 1), Vector2i(2, 1), "dark_room")
	var fog: Node2D = FOG_OF_WAR.new() as Node2D
	fog.cell_size = Vector2i(8, 8)
	fog.chunk_size_pixels = Vector2i(320, 180)
	fog.call("bind_player", player)
	var source := PersistenceSource.new()
	root.add_child(source)
	fog.bind_persistence_source(source)
	root.add_child(fog)
	add_child(root)
	var room: Resource = _make_room("dark_room", Vector2i.ZERO, Vector2i(1, 1))
	fog.call("bind_room", room, terrain, Vector2i.ZERO)
	if fog.is_cell_lit(Vector2i(1, 1)):
		failures.append("dark zone cell was lit before the player entered")
	if source.revealed_zones.size() != 0:
		failures.append("dark zone was revealed without the player entering")
	player.position = Vector2(12.0, 12.0)
	fog.call("bind_player", player)
	fog.call("reveal_from_player")
	if not fog.is_cell_lit(Vector2i(1, 1)):
		failures.append("dark zone did not light after the player entered")
	if not source.revealed_zones.has("dark_room:dark_room"):
		failures.append("revealed dark zone was not persisted")
	zone.free()
	root.free()


func _assert_restore_and_focus(failures: Array[String]) -> void:
	var root := Node2D.new()
	var player := Node2D.new()
	player.position = Vector2(52.0, 12.0)
	root.add_child(player)
	var terrain := _make_terrain({})
	root.add_child(terrain)
	var zone := _make_zone(root, DARK_MODE, Vector2i(1, 1), Vector2i(4, 4), "restore_zone")
	zone.set("restore_on_exit", true)
	zone.set("focus_room", true)
	zone.set("focus_seconds", 0.05)
	var fog: Node2D = FOG_OF_WAR.new() as Node2D
	fog.cell_size = Vector2i(8, 8)
	fog.chunk_size_pixels = Vector2i(320, 180)
	fog.call("bind_player", player)
	root.add_child(fog)
	add_child(root)
	var room: Resource = _make_room("restore_room", Vector2i.ZERO, Vector2i(1, 1))
	fog.call("bind_room", room, terrain, Vector2i.ZERO)
	if fog.is_focus_active():
		failures.append("focus started before the player entered the zone")
	player.position = Vector2(24.0, 24.0)
	fog.call("bind_player", player)
	fog.call("reveal_from_player")
	if not fog.is_cell_lit(Vector2i(2, 2)):
		failures.append("restore zone did not light while the player was inside")
	if not fog.is_focus_active():
		failures.append("focus did not start inside the focus zone")
	if not bool(zone.get("seen")):
		failures.append("focus zone was not marked as seen")
	player.position = Vector2(52.0, 12.0)
	fog.call("bind_player", player)
	fog.call("reveal_from_player")
	if fog.is_focus_active():
		failures.append("focus did not end after leaving the zone")
	if fog.is_cell_lit(Vector2i(2, 2)):
		failures.append("restore zone stayed lit after the player left")
	if not fog.is_cell_explored(Vector2i(2, 2)):
		failures.append("restore zone lost its explored state")
	zone.free()
	root.free()


func _assert_partial_overlap_lights_both_sides(failures: Array[String]) -> void:
	var root := Node2D.new()
	var player := Node2D.new()
	player.position = Vector2(52.0, 12.0)
	root.add_child(player)
	var terrain := _make_terrain({})
	root.add_child(terrain)
	var zone := _make_zone(root, DARK_MODE, Vector2i(1, 1), Vector2i(2, 1), "partial_zone")
	zone.set("restore_on_exit", true)
	zone.set("focus_room", true)
	var fog: Node2D = FOG_OF_WAR.new() as Node2D
	fog.cell_size = Vector2i(8, 8)
	fog.chunk_size_pixels = Vector2i(320, 180)
	fog.call("bind_player", player)
	root.add_child(fog)
	add_child(root)
	var room: Resource = _make_room("partial_room", Vector2i.ZERO, Vector2i(1, 1))
	fog.call("bind_room", room, terrain, Vector2i.ZERO)
	# Feet at y=10: the hero overlaps the zone's lower edge but its head is above
	# the zone, so it is only partially inside.
	player.position = Vector2(16.0, 10.0)
	fog.call("bind_player", player)
	fog.call("reveal_from_player")
	if not fog.is_cell_lit(Vector2i(1, 1)):
		failures.append("partially overlapping dark zone stayed black")
	if fog.is_focus_active():
		failures.append("focus started while the hero was only partially inside")
	player.position = Vector2(52.0, 12.0)
	fog.call("bind_player", player)
	fog.call("reveal_from_player")
	if fog.is_cell_lit(Vector2i(1, 1)):
		failures.append("partially overlapping zone did not darken after a full exit")
	zone.free()
	root.free()


func _assert_sub_cell_zone_edge_refreshes(failures: Array[String]) -> void:
	var root := Node2D.new()
	var player := Node2D.new()
	player.position = Vector2(2.0, 10.0)
	root.add_child(player)
	var terrain := _make_terrain({})
	root.add_child(terrain)
	var zone := _make_zone(root, DARK_MODE, Vector2i(1, 1), Vector2i(1, 1), "edge_zone")
	var fog: Node2D = FOG_OF_WAR.new() as Node2D
	fog.cell_size = Vector2i(8, 8)
	fog.chunk_size_pixels = Vector2i(320, 180)
	fog.call("bind_player", player)
	root.add_child(fog)
	add_child(root)
	var room: Resource = _make_room("edge_room", Vector2i.ZERO, Vector2i(1, 1))
	fog.call("bind_room", room, terrain, Vector2i.ZERO)
	if fog.is_cell_lit(Vector2i(1, 1)):
		failures.append("zone lit before the hero touched it")
	# Same fog cell (0), but the body now reaches across the zone edge.
	player.position = Vector2(6.0, 10.0)
	fog.call("_process", 0.0)
	if not fog.is_cell_lit(Vector2i(1, 1)):
		failures.append("sub-cell movement across a zone edge did not refresh the fog")
	zone.free()
	root.free()


func _assert_door_occludes_sight(failures: Array[String]) -> void:
	var root := Node2D.new()
	var terrain := _make_terrain({})
	root.add_child(terrain)
	var door := FakeOccluder.new()
	door.position = Vector2(24, 8)
	root.add_child(door)
	var fog: Node2D = FOG_OF_WAR.new() as Node2D
	fog.cell_size = Vector2i(8, 8)
	fog.chunk_size_pixels = Vector2i(320, 180)
	root.add_child(fog)
	add_child(root)
	var room: Resource = _make_room("door_room", Vector2i.ZERO, Vector2i(1, 1))
	fog.call("bind_room", room, terrain, Vector2i.ZERO)
	var blockers: Dictionary = fog.call("_collect_sight")
	if not blockers.has(Vector2i(3, 1)):
		failures.append("closed door did not block sight")
	door.occluding = false
	fog.call("request_refresh")
	var opened: Dictionary = fog.call("_collect_sight")
	if opened.has(Vector2i(3, 1)):
		failures.append("open door kept blocking sight")
	door.free()
	root.free()


func _assert_cell_occluder_participates(failures: Array[String]) -> void:
	# This is the shape a sliding puzzle piece exposes: wall cells plus one-way
	# cells in world coordinates, with no rectangular bounding box.
	var root := Node2D.new()
	var terrain := _make_terrain({})
	root.add_child(terrain)
	var occluder := FakeCellOccluder.new()
	occluder.cells = [Vector2i(3, 1), Vector2i(3, 2)]
	occluder.one_way_cells = [Vector2i(4, 1)]
	root.add_child(occluder)
	var fog: Node2D = FOG_OF_WAR.new() as Node2D
	fog.cell_size = Vector2i(8, 8)
	fog.chunk_size_pixels = Vector2i(320, 180)
	root.add_child(fog)
	add_child(root)
	var room: Resource = _make_room("slider_room", Vector2i.ZERO, Vector2i(1, 1))
	fog.call("bind_room", room, terrain, Vector2i.ZERO)
	var blockers: Dictionary = fog.call("_collect_sight")
	var one_way: Dictionary = fog.get("_one_way_cells")
	for cell: Vector2i in [Vector2i(3, 1), Vector2i(3, 2)]:
		if not blockers.has(cell):
			failures.append("cell occluder wall cell %s did not block sight" % cell)
	if not one_way.has(Vector2i(4, 1)):
		failures.append("cell occluder one-way cell did not participate")
	occluder.occluding = false
	fog.call("request_refresh")
	var opened: Dictionary = fog.call("_collect_sight")
	if opened.has(Vector2i(3, 1)):
		failures.append("disabled cell occluder kept blocking sight")
	occluder.free()
	root.free()


func _assert_room_switch_clears_state(failures: Array[String]) -> void:
	var fog: Node2D = FOG_OF_WAR.new() as Node2D
	fog.cell_size = Vector2i(8, 8)
	fog.chunk_size_pixels = Vector2i(320, 180)
	var source := PersistenceSource.new()
	fog.bind_persistence_source(source)
	source.explored_cells = ["room_b:40,0"]
	var room_a: Resource = _make_room("room_a", Vector2i.ZERO, Vector2i(1, 1))
	var room_b: Resource = _make_room("room_b", Vector2i(1, 0), Vector2i(1, 1))
	var terrain_a := _make_terrain({})
	var terrain_b := _make_terrain({})
	if fog.call("bind_room", room_a, terrain_a, Vector2i.ZERO) != true:
		failures.append("FogOfWar rejected the first room binding")
	fog.call("reveal_from_cell", Vector2i.ZERO, {})
	if fog.currently_visible.is_empty() or fog.get_mask_image() == null:
		failures.append("FogOfWar first room did not produce visible state and mask")
	if fog.call("bind_room", room_b, terrain_b, Vector2i(1, 0)) != true:
		failures.append("FogOfWar rejected the second room binding")
	else:
		if fog.is_cell_explored(Vector2i.ZERO):
			failures.append("room switch retained explored cells from the old room")
		if not fog.is_cell_explored(Vector2i(40, 0)):
			failures.append("room switch did not load persisted exploration for the new room")
		if fog.get_mask_image() != null or fog.get_mask_texture() != null:
			failures.append("room switch retained the old fog mask")
	fog.call("clear_room")
	if fog.get_mask_image() != null or not fog.currently_visible.is_empty():
		failures.append("clear_room did not clear visible state")
	terrain_a.free()
	terrain_b.free()
	fog.free()
	source.free()


func _assert_mask_matches_lit_cells(failures: Array[String]) -> void:
	var fog: Node2D = FOG_OF_WAR.new() as Node2D
	fog.map_origin_cell = Vector2i(0, 0)
	fog.map_size_cells = Vector2i(4, 1)
	fog.cell_size = Vector2i(8, 8)
	fog.reveal_from_cell(Vector2i(0, 0), {Vector2i(1, 0): true})
	# The mask fades revealed cells out over reveal_seconds, so read the settled
	# state to keep asserting the shape of the fog rather than the wave.
	fog.call("_update_mask_image", 1000.0)
	var mask: Image = fog.get_mask_image()
	if mask == null:
		failures.append("fog mask image was not created")
	elif mask.get_size() != Vector2i(32, 8):
		failures.append("fog mask image did not match room pixel size")
	elif mask.get_pixel(4, 4).a != 0.0:
		failures.append("visible fog mask pixel was not transparent")
	elif mask.get_pixel(12, 4).a != 0.0:
		failures.append("blocking fog mask pixel was not transparent")
	elif mask.get_pixel(20, 4).a <= 0.9:
		failures.append("unreached fog mask pixel was not opaque")
	if fog.get_mask_texture() == null:
		failures.append("fog mask texture was not created")
	fog.free()


func _assert_mask_reveal_wave_animates(failures: Array[String]) -> void:
	var fog: Node2D = FOG_OF_WAR.new() as Node2D
	fog.map_origin_cell = Vector2i(0, 0)
	fog.map_size_cells = Vector2i(4, 1)
	fog.cell_size = Vector2i(8, 8)
	fog.reveal_seconds = 0.5
	fog.reveal_flash_seconds = 0.2
	fog.reveal_from_cell(Vector2i(0, 0), {Vector2i(1, 0): true})
	var wave: Image = fog.get_mask_image()
	if wave == null:
		failures.append("fog mask was not created for the reveal wave")
		fog.free()
		return
	if wave.get_pixel(4, 4).a < 0.5:
		failures.append("a cell mid reveal wave should still hold its fog")
	if wave.get_pixel(4, 4).r <= 0.0:
		failures.append("a cell that just opened should carry a reveal flash")
	if not bool(fog.call("_mask_animating", float(Time.get_ticks_msec()) / 1000.0)):
		failures.append("fog mask stopped animating before the wave finished")
	fog.call("_update_mask_image", 1000.0)
	var settled: Image = fog.get_mask_image()
	if settled.get_pixel(4, 4).a != 0.0:
		failures.append("fog mask kept a revealed cell opaque after the wave")
	if settled.get_pixel(4, 4).r != 0.0:
		failures.append("fog mask kept a reveal flash after the wave")
	if bool(fog.call("_mask_animating", 1000.0)):
		failures.append("fog mask kept animating after the wave settled")
	fog.free()


func _assert_mask_quad_follows_room(failures: Array[String]) -> void:
	var root := get_tree().root
	var fog: Node2D = FOG_OF_WAR.new() as Node2D
	root.add_child(fog)
	fog.call("set_room_chunks", Vector2i.ONE, Vector2i.ONE)
	fog.call("reveal_from_cell", fog.map_origin_cell, {})
	var quad := fog.get_node_or_null("FogMask") as Sprite2D
	if quad == null:
		failures.append("fog did not create its mask quad")
	else:
		if quad.texture == null or quad.texture != fog.get_mask_texture():
			failures.append("fog mask quad did not show the current mask texture")
		if quad.texture_filter != CanvasItem.TEXTURE_FILTER_NEAREST:
			failures.append("fog mask quad would blur the mask while scaling")
		if not (quad.material is ShaderMaterial):
			failures.append("fog mask quad was not driven by the fog shader")
		if quad.position != Vector2(fog.get_mask_origin_pixels()):
			failures.append("fog mask quad did not sit at the room origin")
		if quad.texture != null and quad.texture.get_size() != Vector2(fog.get_mask_size_pixels()):
			failures.append("fog mask quad size drifted from the room bounds")
	fog.call("clear_room")
	if quad != null and quad.texture != null:
		failures.append("clearing the room kept the stale mask on screen")
	root.remove_child(fog)
	fog.free()


func _assert_saved_exploration_updates_mask(failures: Array[String]) -> void:
	var fog: Node2D = FOG_OF_WAR.new() as Node2D
	fog.level_id = "saved_room"
	fog.map_origin_cell = Vector2i.ZERO
	fog.map_size_cells = Vector2i(4, 1)
	fog.cell_size = Vector2i(8, 8)
	var saved_cells: Array[String] = ["saved_room:2,0"]
	fog.load_explored_cells(saved_cells)
	fog.call("_update_mask_image")
	var mask: Image = fog.get_mask_image()
	if mask == null or mask.get_pixel(20, 4).a != 0.0:
		failures.append("saved fog exploration was not transparent in the mask")
	fog.free()


## A dark zone has to dissolve, not switch off: the mask has to show in-between
## opacity for a moment after the hero enters, and it has to ramp back up (never
## jump straight to opaque) after a restore_on_exit exit.
func _assert_zone_fade_is_gradual(failures: Array[String]) -> void:
	var root := Node2D.new()
	var player := Node2D.new()
	player.position = Vector2(52.0, 12.0)
	root.add_child(player)
	var terrain := _make_terrain({})
	root.add_child(terrain)
	var zone := _make_zone(root, DARK_MODE, Vector2i(1, 1), Vector2i(4, 4), "fade_zone")
	zone.set("restore_on_exit", true)
	var fog: Node2D = FOG_OF_WAR.new() as Node2D
	fog.cell_size = Vector2i(8, 8)
	fog.chunk_size_pixels = Vector2i(320, 180)
	fog.zone_reveal_seconds = 0.9
	fog.zone_reveal_stagger = 0.02
	fog.zone_restore_seconds = 0.8
	fog.zone_restore_stagger = 0.02
	fog.call("bind_player", player)
	root.add_child(fog)
	add_child(root)
	var room: Resource = _make_room("fade_room", Vector2i.ZERO, Vector2i(1, 1))
	fog.call("bind_room", room, terrain, Vector2i.ZERO)
	var inside := Vector2i(2, 2)
	if fog.get_mask_image().get_pixel(20, 20).a < 0.9:
		failures.append("unrevealed dark zone was not opaque before the hero entered")
	var opened_at := float(Time.get_ticks_msec()) / 1000.0
	player.position = Vector2(24.0, 24.0)
	fog.call("bind_player", player)
	fog.call("reveal_from_player")
	fog.call("_update_mask_image", opened_at + 0.45)
	var opening: float = fog.get_mask_image().get_pixel(20, 20).a
	if opening <= 0.15 or opening >= 0.85:
		failures.append("dark zone did not fade in, opacity jumped to %.3f" % opening)
	if not bool(fog.call("_mask_animating", opened_at + 0.45)):
		failures.append("fog stopped animating while the zone fade was in flight")
	fog.call("_update_mask_image", opened_at + 100.0)
	if fog.get_mask_image().get_pixel(20, 20).a > 0.05:
		failures.append("dark zone never finished fading in")
	if bool(fog.call("_mask_animating", opened_at + 100.0)):
		failures.append("fog kept animating after the zone fade settled")

	var closed_at := float(Time.get_ticks_msec()) / 1000.0
	player.position = Vector2(52.0, 12.0)
	fog.call("bind_player", player)
	fog.call("reveal_from_player")
	if fog.is_cell_lit(inside):
		failures.append("restore zone did not re-darken after the hero left")
	fog.call("_update_mask_image", closed_at)
	var closing: float = fog.get_mask_image().get_pixel(20, 20).a
	if closing > 0.5:
		failures.append("restored zone snapped back to opaque (%.3f) instead of closing" % closing)
	fog.call("_update_mask_image", closed_at + 100.0)
	if fog.get_mask_image().get_pixel(20, 20).a < 0.95:
		failures.append("restored zone never became opaque again")
	zone.free()
	root.free()


## The focus spotlight is a shader term now, because it follows the hero every
## frame. What the mask material must receive: the zone rectangle, a strength that
## ramps up, and a centre that tracks the player.
## Flipping a fade back mid-wave must not teleport the block: each cell keeps its
## own start opacity, so the zone stays continuous when the hero steps back in
## while it is still opening (that reversal is what a player triggers by walking
## along a zone edge).
func _assert_fade_reversal_stays_continuous(failures: Array[String]) -> void:
	var root := Node2D.new()
	var player := Node2D.new()
	player.position = Vector2(52.0, 12.0)
	root.add_child(player)
	var terrain := _make_terrain({})
	root.add_child(terrain)
	var zone := _make_zone(root, DARK_MODE, Vector2i(1, 1), Vector2i(6, 6), "reversal_zone")
	zone.set("restore_on_exit", true)
	var fog: Node2D = FOG_OF_WAR.new() as Node2D
	fog.cell_size = Vector2i(8, 8)
	fog.chunk_size_pixels = Vector2i(320, 180)
	fog.zone_reveal_seconds = 0.9
	fog.zone_reveal_stagger = 0.02
	fog.zone_restore_seconds = 0.8
	fog.zone_restore_stagger = 0.02
	fog.call("bind_player", player)
	root.add_child(fog)
	add_child(root)
	var room: Resource = _make_room("reversal_room", Vector2i.ZERO, Vector2i(1, 1))
	fog.call("bind_room", room, terrain, Vector2i.ZERO)
	var opened_at := float(Time.get_ticks_msec()) / 1000.0
	player.position = Vector2(24.0, 24.0)
	fog.call("bind_player", player)
	fog.call("reveal_from_player")
	# Halfway through the opening wave, walk back out.
	fog.call("_update_mask_image", opened_at + 0.45)
	var before := _mask_alpha_samples(fog)
	var closed_at := float(Time.get_ticks_msec()) / 1000.0
	player.position = Vector2(52.0, 12.0)
	fog.call("bind_player", player)
	fog.call("reveal_from_player")
	fog.call("_update_mask_image", closed_at)
	var after := _mask_alpha_samples(fog)
	if before.size() != after.size() or before.is_empty():
		failures.append("fade reversal produced no samples")
	else:
		var biggest := 0.0
		for index: int in before.size():
			biggest = maxf(biggest, absf(before[index] - after[index]))
		# A single frame of either fade moves at most a few hundredths; picking one
		# cell's value for the whole block used to jump by ~0.1 or more.
		if biggest > 0.06:
			failures.append("fade reversal jumped %.3f in one frame" % biggest)
	zone.free()
	root.free()


## Opacity of a few fixed cells of the last zone, in a stable order.
func _mask_alpha_samples(fog: Node2D) -> PackedFloat32Array:
	var samples := PackedFloat32Array()
	var mask: Image = fog.call("get_mask_image")
	if mask == null:
		return samples
	for cell: Vector2i in [
		Vector2i(2, 2), Vector2i(3, 3), Vector2i(4, 2), Vector2i(2, 4), Vector2i(5, 5)
	]:
		var rect: Rect2i = fog.call("_mask_cell_rect", cell)
		if rect.size.x <= 0 or rect.size.y <= 0:
			continue
		samples.append(mask.get_pixel(rect.position.x, rect.position.y).a)
	return samples


func _assert_focus_spotlight_reaches_the_shader(failures: Array[String]) -> void:
	var root := Node2D.new()
	var player := Node2D.new()
	player.position = Vector2(52.0, 12.0)
	root.add_child(player)
	var terrain := _make_terrain({})
	root.add_child(terrain)
	var zone := _make_zone(root, DARK_MODE, Vector2i(1, 1), Vector2i(4, 4), "spotlight_zone")
	zone.set("focus_room", true)
	zone.set("focus_seconds", 0.05)
	zone.set("focus_alpha", 0.9)
	var fog: Node2D = FOG_OF_WAR.new() as Node2D
	fog.cell_size = Vector2i(8, 8)
	fog.chunk_size_pixels = Vector2i(320, 180)
	fog.focus_radius_px = 30.0
	fog.focus_falloff_px = 26.0
	fog.call("bind_player", player)
	root.add_child(fog)
	add_child(root)
	var room: Resource = _make_room("spotlight_room", Vector2i.ZERO, Vector2i(1, 1))
	fog.call("bind_room", room, terrain, Vector2i.ZERO)
	player.position = Vector2(24.0, 24.0)
	fog.call("bind_player", player)
	fog.call("reveal_from_player")
	fog.call("_update_mask_image")
	OS.delay_msec(90)
	fog.call("_process", 0.016)
	var quad := fog.get_node_or_null("FogMask") as Sprite2D
	if quad == null or not (quad.material is ShaderMaterial):
		failures.append("fog mask material missing, the spotlight cannot be shaded")
		zone.free()
		root.free()
		return
	var material := quad.material as ShaderMaterial
	var strength := float(material.get_shader_parameter("focus_strength"))
	if strength <= 0.5:
		failures.append("focus strength did not ramp up (%.3f)" % strength)
	var rect: Vector4 = material.get_shader_parameter("focus_rect_px")
	if rect.z <= 0.0 or rect.w <= 0.0:
		failures.append("focus zone rectangle never reached the shader")
	var first_center: Vector2 = material.get_shader_parameter("focus_center_px")
	player.position = Vector2(32.0, 24.0)
	fog.call("bind_player", player)
	fog.call("_process", 0.016)
	var moved_center: Vector2 = material.get_shader_parameter("focus_center_px")
	if is_equal_approx(first_center.x, moved_center.x):
		failures.append("focus spotlight did not follow the hero")
	if float(material.get_shader_parameter("focus_falloff_px")) <= 0.0:
		failures.append("focus falloff never reached the shader, so it cannot be a gradient")
	zone.free()
	root.free()


func _make_room(room_id: String, _origin_chunk: Vector2i, size: Vector2i = Vector2i.ONE) -> Resource:
	var room: Resource = ROOM_DATA.new()
	room.room_id = room_id
	room.room_size_chunks = size
	return room


func _make_terrain(cells: Dictionary) -> Node2D:
	var root := Node2D.new()
	var background := Node2D.new()
	background.name = "Background"
	root.add_child(background)
	var terrain := Node2D.new()
	terrain.name = "Terrain"
	root.add_child(terrain)
	var tile_set := _make_tileset()
	for layer_name: String in LAYER_NAMES:
		var layer := TileMapLayer.new()
		layer.name = layer_name
		layer.tile_set = tile_set
		layer.collision_enabled = layer_name == "SolidTiles"
		terrain.add_child(layer)
	var solid := terrain.get_node("SolidTiles") as TileMapLayer
	for cell: Vector2i in cells:
		solid.set_cell(cell, 0, cells[cell])
	return root


func _make_zone(root: Node2D, mode: int, cell: Vector2i, size: Vector2i, zone_id: String) -> Node2D:
	var zone: Node2D = FOG_ZONE.new() as Node2D
	zone.mode = mode
	zone.size_cells = size
	zone.zone_id = zone_id
	zone.position = Vector2(cell * 8)
	root.add_child(zone)
	return zone


func _make_tileset() -> TileSet:
	var tile_set := TileSet.new()
	tile_set.tile_size = Vector2i(8, 8)
	tile_set.add_physics_layer()
	tile_set.set_physics_layer_collision_layer(0, 1)
	tile_set.set_physics_layer_collision_mask(0, 2)
	var source := TileSetAtlasSource.new()
	var image := Image.create(32, 64, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	source.texture = ImageTexture.create_from_image(image)
	source.texture_region_size = Vector2i(8, 8)
	for coords: Vector2i in [SOLID_TILE, ONE_WAY_TILE, PLAIN_TILE, GLASS_TILE, CRUMBLE_SOLID_TILE, CRUMBLE_ONE_WAY_TILE]:
		source.create_tile(coords)
	tile_set.add_source(source, 0)
	_add_full_polygon(source, SOLID_TILE)
	_add_full_polygon(source, GLASS_TILE)
	_add_full_polygon(source, CRUMBLE_SOLID_TILE)
	_add_one_way_polygon(source, ONE_WAY_TILE)
	_add_one_way_polygon(source, CRUMBLE_ONE_WAY_TILE)
	return tile_set


func _add_full_polygon(source: TileSetAtlasSource, coords: Vector2i) -> void:
	var data := source.get_tile_data(coords, 0)
	data.add_collision_polygon(0)
	data.set_collision_polygon_points(0, 0, PackedVector2Array([
		Vector2(-4, -4), Vector2(4, -4), Vector2(4, 4), Vector2(-4, 4)
	]))


func _add_one_way_polygon(source: TileSetAtlasSource, coords: Vector2i) -> void:
	var data := source.get_tile_data(coords, 0)
	data.add_collision_polygon(0)
	data.set_collision_polygon_points(0, 0, PackedVector2Array([
		Vector2(-4, -1), Vector2(4, -1), Vector2(4, -4), Vector2(-4, -4)
	]))
	data.set_collision_polygon_one_way(0, 0, true)
