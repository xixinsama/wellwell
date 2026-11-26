class_name AutopilotGrid
extends RefCounted

## Traversal map for the autopilot planner.
##
## The map is rasterized once per room: a 4 px solid mask carries collision at
## sub-tile resolution, 8 px nav cells aligned to the tile grid carry footholds
## and ladder footprints. After [method build] the planner only reads arrays, so
## route solving is deterministic and can be unit tested without a physics world.

const NAV_CELL_SIZE := 8
const FINE_CELL_SIZE := 4
## The raster is shared by a tool, its worker thread and any probe that reaches
## for it; every writer and every simulator goes through this guard.
const AUTOPILOT_LOCK = preload("res://addons/platformer_kit/character/autopilot/autopilot_lock.gd")
## Ownership guard for the shared movement state in [method move_box]. The
## planner holds it for a whole search, the scan holds it per step, and a probe
## that does not hold it gets [code]null[/code] legs instead of garbage.
var lock = AUTOPILOT_LOCK.new()
## Cells rasterized past the room edge, so boundary walls are real geometry.
const MARGIN_CELLS := 2
const INVALID_CELL := Vector2i(-99999, -99999)

## Solid map cell rectangle in 4 px cells.
var fine_rect := Rect2i()
## Navigation cell rectangle in 8 px cells.
var nav_rect := Rect2i()
var body_size := Vector2(6.0, 6.0)
## Collision shape centre relative to the character origin (feet).
var body_offset := Vector2(0.0, -3.0)
## Physics layers the character collides with.
var collision_mask := 1

var _solid := PackedByteArray()
## Cells that only block a falling body (one-way platforms).
var _one_way := PackedByteArray()
var _standable := PackedByteArray()
var _ladder := PackedByteArray()
var _ladder_rects: Array[Rect2] = []

## Results of the last [method move_box] call: no per-tick allocations.
var last_move_position := Vector2.ZERO
var last_move_hit_x := false
var last_move_hit_y := false
## Pixels of air the simulated body keeps from surfaces. Tile collision is a
## fraction of a pixel larger than the raster, so a trajectory planned exactly on
## a corner makes the live body bounce out instead of sliding past.
var motion_clearance := 1.2


## Rasterize the live physics world. [param avoid_rects] are painted into the
## solid mask, so hazards and kill zones are treated as impassable instead of
## letting the planner route through them.
func build(
	space: PhysicsDirectSpaceState2D,
	cell_rect: Rect2i,
	ladder_rects: Array[Rect2],
	avoid_rects: Array[Rect2] = []
) -> bool:
	if not begin_build(space, cell_rect, ladder_rects, avoid_rects):
		return false
	while not build_step(64, 64):
		pass
	return true


const PHASE_IDLE := 0
const PHASE_FINE := 1
const PHASE_NAV := 2
const PHASE_DONE := 3

## Incremental rasterization state, so a tool can spread the scan over frames.
var _build_phase := PHASE_IDLE
var _build_space: PhysicsDirectSpaceState2D
var _build_fine_y := 0
var _build_nav_y := 0
var _build_avoid: Array[Rect2] = []
var _build_rows_done := 0
var _build_rows_total := 0


## Start rasterizing without doing the work: [method build_step] finishes it in
## slices, which lets the caller draw a scan effect and keep the frame smooth.
func begin_build(
	space: PhysicsDirectSpaceState2D,
	cell_rect: Rect2i,
	ladder_rects: Array[Rect2],
	avoid_rects: Array[Rect2] = []
) -> bool:
	if space == null or cell_rect.size.x <= 0 or cell_rect.size.y <= 0:
		return false
	nav_rect = cell_rect
	# Rasterize two cells past the room so a real wall just outside the edge is
	# seen as a wall, while the room boundary itself is not a phantom wall.
	var grown := cell_rect.grow(MARGIN_CELLS)
	fine_rect = Rect2i(grown.position * 2, grown.size * 2)
	_ladder_rects = ladder_rects.duplicate()
	_solid.resize(fine_rect.size.x * fine_rect.size.y)
	_solid.fill(0)
	_one_way.resize(fine_rect.size.x * fine_rect.size.y)
	_one_way.fill(0)
	_standable.resize(nav_rect.size.x * nav_rect.size.y)
	_standable.fill(0)
	_ladder.resize(nav_rect.size.x * nav_rect.size.y)
	_ladder.fill(0)
	_build_space = space
	_build_avoid = avoid_rects.duplicate()
	_build_phase = PHASE_FINE
	_build_fine_y = fine_rect.position.y
	_build_nav_y = nav_rect.position.y
	_build_rows_done = 0
	_build_rows_total = maxi(fine_rect.size.y + nav_rect.size.y, 1)
	return true


## Advance the raster by [param fine_rows] fine rows and [param nav_rows] nav
## rows. Returns true once the map is complete.
func build_step(fine_rows: int = 4, nav_rows: int = 6) -> bool:
	if not lock.try_acquire(&"scan"):
		# Someone is planning on this raster right now; do not write under them.
		return _build_phase == PHASE_DONE
	if _build_phase == PHASE_FINE:
		var until := mini(_build_fine_y + maxi(fine_rows, 1), fine_rect.end.y)
		for fy: int in range(_build_fine_y, until):
			_build_fine_row(fy)
		_build_rows_done += until - _build_fine_y
		_build_fine_y = until
		if _build_fine_y >= fine_rect.end.y:
			_build_phase = PHASE_NAV
	if _build_phase == PHASE_NAV:
		var until := mini(_build_nav_y + maxi(nav_rows, 1), nav_rect.end.y)
		for cy: int in range(_build_nav_y, until):
			_build_nav_row(cy)
		_build_rows_done += until - _build_nav_y
		_build_nav_y = until
		if _build_nav_y >= nav_rect.end.y:
			_finish_build()
			_build_phase = PHASE_DONE
	var finished := _build_phase == PHASE_DONE
	lock.release(&"scan")
	return finished


func is_building() -> bool:
	return _build_phase == PHASE_FINE or _build_phase == PHASE_NAV


## 0..1 scan progress, for a HUD or a scan effect.
func build_progress() -> float:
	if _build_phase == PHASE_DONE:
		return 1.0
	return clampf(float(_build_rows_done) / float(maxi(_build_rows_total, 1)), 0.0, 1.0)


## World y of the scan line, so an effect can follow the rasterization.
func build_scan_y() -> float:
	if _build_phase == PHASE_FINE:
		return float(_build_fine_y * FINE_CELL_SIZE)
	if _build_phase == PHASE_NAV:
		return float(_build_nav_y * NAV_CELL_SIZE)
	return float(nav_rect.end.y * NAV_CELL_SIZE)


func _build_fine_row(fy: int) -> void:
	var fine_shape := RectangleShape2D.new()
	fine_shape.size = Vector2(FINE_CELL_SIZE - 0.2, FINE_CELL_SIZE - 0.2)
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = fine_shape
	query.collision_mask = collision_mask
	for fx: int in range(fine_rect.position.x, fine_rect.end.x):
		var probe := Vector2(
			float(fx * FINE_CELL_SIZE) + FINE_CELL_SIZE * 0.5,
			float(fy * FINE_CELL_SIZE) + FINE_CELL_SIZE * 0.5
		)
		query.transform = Transform2D(0.0, probe)
		var hits := _build_space.intersect_shape(query, 8)
		if hits.is_empty():
			continue
		var solid := false
		var one_way := false
		for hit: Dictionary in hits:
			if _hit_is_one_way(hit, probe):
				one_way = true
			else:
				solid = true
				break
		if solid:
			_solid[_fine_index(fx, fy)] = 1
		elif one_way:
			_one_way[_fine_index(fx, fy)] = 1


func _build_nav_row(cy: int) -> void:
	var body_shape := RectangleShape2D.new()
	body_shape.size = body_size - Vector2(0.4, 0.4)
	var body_query := PhysicsShapeQueryParameters2D.new()
	body_query.shape = body_shape
	body_query.collision_mask = collision_mask
	var room_pixels := Rect2(
		Vector2(nav_rect.position) * float(NAV_CELL_SIZE),
		Vector2(nav_rect.size) * float(NAV_CELL_SIZE)
	)
	for cx: int in range(nav_rect.position.x, nav_rect.end.x):
		var origin := cell_to_world(Vector2i(cx, cy))
		var box := Rect2(origin + body_offset - body_size * 0.5, body_size)
		if not room_pixels.encloses(box):
			# A body poking out of the room is not a foothold: the margin is
			# rasterized for collision only.
			continue
		body_query.transform = Transform2D(0.0, origin + body_offset)
		if box_hits(origin):
			continue
		if not _physics_support(_build_space, body_query, origin):
			continue
		_standable[_nav_index(cx, cy)] = 1


func _finish_build() -> void:
	_paint_rects(_build_avoid)
	for cy: int in range(nav_rect.position.y, nav_rect.end.y):
		for cx: int in range(nav_rect.position.x, nav_rect.end.x):
			if _standable[_nav_index(cx, cy)] != 0 and box_hits(cell_to_world(Vector2i(cx, cy))):
				_standable[_nav_index(cx, cy)] = 0
	_mark_ladder_cells()


## True when the collided shape is a one-way platform: a ground-only surface the
## character can jump up through. The flag lives on the shape (body) or on the
## tile's physics polygon, so it is read from the collider, never guessed.
func _hit_is_one_way(hit: Dictionary, probe: Vector2) -> bool:
	var collider = hit.get("collider")
	if collider == null:
		return false
	if collider is TileMapLayer:
		# Tile body RIDs are per physics layer, so map the probe position back to
		# its cell instead of trusting get_coords_for_body_rid().
		var layer := collider as TileMapLayer
		var data := layer.get_cell_tile_data(layer.local_to_map(layer.to_local(probe)))
		return _tile_data_is_one_way(data, layer.tile_set)
	if collider is CollisionObject2D:
		var object := collider as CollisionObject2D
		var owner_id := object.shape_find_owner(int(hit.get("shape", 0)))
		if owner_id < 0:
			return false
		return object.is_shape_owner_one_way_collision_enabled(owner_id)
	return false


## A tile is one-way when all of its collision polygons are one-way.
func _tile_data_is_one_way(data: TileData, tileset: TileSet) -> bool:
	if data == null or tileset == null:
		return false
	var any_one_way := false
	for layer_id: int in range(tileset.get_physics_layers_count()):
		for polygon: int in range(data.get_collision_polygons_count(layer_id)):
			if data.is_collision_polygon_one_way(layer_id, polygon):
				any_one_way = true
			else:
				return false
	return any_one_way


## Synthetic map for tools and tests: `#` solid, `-` one-way platform (passable
## from below), `=` foothold, `L` ladder. Row 0 is the top row, column 0 the left
## column.
func build_from_rows(rows: Array[String]) -> bool:
	if rows.is_empty():
		return false
	var width := 0
	for row: String in rows:
		width = maxi(width, row.length())
	if width <= 0:
		return false
	nav_rect = Rect2i(Vector2i.ZERO, Vector2i(width, rows.size()))
	fine_rect = Rect2i(Vector2i.ZERO, Vector2i(width * 2, rows.size() * 2))
	_ladder_rects.clear()
	_solid.resize(fine_rect.size.x * fine_rect.size.y)
	_solid.fill(0)
	_one_way.resize(fine_rect.size.x * fine_rect.size.y)
	_one_way.fill(0)
	_standable.resize(nav_rect.size.x * nav_rect.size.y)
	_standable.fill(0)
	_ladder.resize(nav_rect.size.x * nav_rect.size.y)
	_ladder.fill(0)
	for cy: int in range(rows.size()):
		var row: String = rows[cy]
		for cx: int in range(row.length()):
			var symbol := row[cx]
			if symbol == "#":
				_solid[_fine_index(cx * 2, cy * 2)] = 1
				_solid[_fine_index(cx * 2 + 1, cy * 2)] = 1
				_solid[_fine_index(cx * 2, cy * 2 + 1)] = 1
				_solid[_fine_index(cx * 2 + 1, cy * 2 + 1)] = 1
			elif symbol == "-":
				# The shipped one-way tile carries an 8 x 4 collider in the *upper*
				# half of its cell, so only those fine rows are one-way. Marking the
				# whole cell would make the synthetic benchmark disagree with the
				# live raster in exactly the place jumps are measured.
				_one_way[_fine_index(cx * 2, cy * 2)] = 1
				_one_way[_fine_index(cx * 2 + 1, cy * 2)] = 1
			elif symbol == "L":
				_ladder_rects.append(
					Rect2(float(cx * NAV_CELL_SIZE), float(cy * NAV_CELL_SIZE), 8.0, 8.0)
				)
	_mark_ladder_cells()
	var room_pixels := Rect2(
		Vector2(nav_rect.position) * float(NAV_CELL_SIZE),
		Vector2(nav_rect.size) * float(NAV_CELL_SIZE)
	)
	for cy: int in range(nav_rect.position.y, nav_rect.end.y):
		for cx: int in range(nav_rect.position.x, nav_rect.end.x):
			var cell := Vector2i(cx, cy)
			var origin := cell_to_world(cell)
			var box := Rect2(origin + body_offset - body_size * 0.5, body_size)
			if not room_pixels.encloses(box):
				continue
			if not cell_is_free(cell):
				continue
			var forced := rows[cy][cx] == "=" if cx < rows[cy].length() else false
			if forced or is_supported(origin):
				_standable[_nav_index(cx, cy)] = 1
	return true


func is_built() -> bool:
	return nav_rect.size.x > 0 and nav_rect.size.y > 0


func cell_to_world(cell: Vector2i) -> Vector2:
	return Vector2(float(cell.x * NAV_CELL_SIZE), float(cell.y * NAV_CELL_SIZE))


func world_to_cell(world_position: Vector2) -> Vector2i:
	return Vector2i(
		floori(world_position.x / float(NAV_CELL_SIZE)),
		floori(world_position.y / float(NAV_CELL_SIZE))
	)


func has_cell(cell: Vector2i) -> bool:
	return nav_rect.has_point(cell)


func cell_is_free(cell: Vector2i) -> bool:
	if not has_cell(cell):
		return false
	return not box_hits(cell_to_world(cell))


func cell_is_standable(cell: Vector2i) -> bool:
	if not has_cell(cell):
		return false
	return _standable[_nav_index(cell.x, cell.y)] != 0


func cell_is_ladder(cell: Vector2i) -> bool:
	if not has_cell(cell):
		return false
	return _ladder[_nav_index(cell.x, cell.y)] != 0


## True when the cell contains a one-way platform (a surface you can stand on and
## jump up through). Used by the scan overlay to mark them differently.
func cell_has_one_way(cell: Vector2i) -> bool:
	if not has_cell(cell):
		return false
	for dy: int in range(2):
		for dx: int in range(2):
			var fx := cell.x * 2 + dx
			var fy := cell.y * 2 + dy
			if not fine_rect.has_point(Vector2i(fx, fy)):
				continue
			if _one_way[_fine_index(fx, fy)] != 0:
				return true
	return false


## True when the character box at [param origin] overlaps solid terrain.
## One-way platforms are passable from the side and from below.
func box_hits(origin: Vector2) -> bool:
	return _rect_hits(origin + body_offset, body_size, false)


## Same test including one-way platforms, for movement that presses down on them.
func box_hits_supporting(origin: Vector2) -> bool:
	return _rect_hits(origin + body_offset, body_size, true)


## The body grown by [member motion_clearance]: movement keeps a pixel of air so
## the live controller never has to resolve a grazing contact. Only the head
## grows: the feet stay on the origin (so standing works) and the width is
## unchanged (so a wall grab can still slide up).
func box_hits_margin(origin: Vector2, one_way_blocks: bool) -> bool:
	return _rect_hits(
		origin + body_offset + Vector2(0.0, -motion_clearance * 0.5),
		body_size + Vector2(0.0, motion_clearance),
		one_way_blocks
	)


## True when a surface sits within 1.5 px below the character's feet.
func is_supported(origin: Vector2) -> bool:
	return _rect_hits(origin + Vector2(0.0, 1.5) + body_offset, body_size, true)


## True when a vertical face is within 3 px on [param side] (-1 left, 1 right).
func has_wall(origin: Vector2, side: int) -> bool:
	if side == 0:
		return false
	return _rect_hits(origin + Vector2(float(side) * 3.0, -3.0), Vector2(2.0, 4.0), false)


## True when the character box overlaps a ladder footprint at [param origin].
func is_on_ladder(origin: Vector2) -> bool:
	if _ladder_rects.is_empty():
		return false
	var left := origin.x + body_offset.x - body_size.x * 0.5
	var right := origin.x + body_offset.x + body_size.x * 0.5
	var top := origin.y + body_offset.y - body_size.y * 0.5
	var bottom := origin.y + body_offset.y + body_size.y * 0.5
	for ladder_rect: Rect2 in _ladder_rects:
		if (
			left < ladder_rect.end.x
			and right > ladder_rect.position.x
			and top < ladder_rect.end.y
			and bottom > ladder_rect.position.y
		):
			return true
	return false


## Axis-separated movement against the solid mask. The resolved position and the
## stopped axes land in [member last_move_position] / [member last_move_hit_x] /
## [member last_move_hit_y] so the hot loop allocates nothing.
func move_box(origin: Vector2, motion: Vector2) -> void:
	last_move_position = origin
	last_move_hit_x = false
	last_move_hit_y = false
	if motion.is_zero_approx():
		return
	var steps := maxi(1, int(ceil(maxf(absf(motion.x), absf(motion.y)) / 0.5)))
	var step := motion / float(steps)
	var current := origin
	for _index: int in range(steps):
		if not last_move_hit_x and not is_zero_approx(step.x):
			var next_x := current + Vector2(step.x, 0.0)
			if box_hits_margin(next_x, false):
				last_move_hit_x = true
			else:
				current = next_x
		if not last_move_hit_y and not is_zero_approx(step.y):
			var next_y := current + Vector2(0.0, step.y)
			if box_hits_margin(next_y, step.y > 0.0):
				last_move_hit_y = true
			else:
				current = next_y
	last_move_position = current


## Nearest foothold to [param world_position], searching outwards by true
## distance so a diagonal cell never wins over the floor under the feet. A cell
## above the point pays a bias: the floor below the cursor is the better answer.
func find_standable_cell(world_position: Vector2, max_radius: int = 6) -> Vector2i:
	var origin := world_to_cell(world_position)
	for radius: int in range(0, max_radius + 1):
		var best := INVALID_CELL
		var best_distance := INF
		for dy: int in range(-radius, radius + 1):
			for dx: int in range(-radius, radius + 1):
				if maxi(absi(dx), absi(dy)) != radius:
					continue
				var candidate := origin + Vector2i(dx, dy)
				if not cell_is_standable(candidate):
					continue
				var target := cell_to_world(candidate)
				var distance := target.distance_to(world_position)
				if target.y < world_position.y - 1.0:
					distance += 3.0
				if distance < best_distance:
					best_distance = distance
					best = candidate
		if best != INVALID_CELL:
			return best
	return INVALID_CELL


## The nearest cell that can hold a foothold, else the nearest free cell, else
## the cell itself. Used to snap a clicked goal that sits inside a wall.
func find_goal_cell(world_position: Vector2, max_radius: int = 10) -> Vector2i:
	var standable := find_standable_cell(world_position, max_radius)
	if standable != INVALID_CELL:
		return standable
	var origin := world_to_cell(world_position)
	var best := INVALID_CELL
	var best_distance := INF
	for radius: int in range(0, max_radius + 1):
		for dy: int in range(-radius, radius + 1):
			for dx: int in range(-radius, radius + 1):
				if maxi(absi(dx), absi(dy)) != radius:
					continue
				var candidate := origin + Vector2i(dx, dy)
				if not cell_is_free(candidate):
					continue
				var distance := Vector2(float(dx), float(dy)).length()
				if distance < best_distance:
					best_distance = distance
					best = candidate
		if best != INVALID_CELL:
			return best
	return INVALID_CELL


## How much open air surrounds a cell, in nav cells, capped at [param limit].
## Used to prefer routes that keep away from walls and ceilings: a leg that ends
## in the middle of a room replays far more reliably than one grazing a corner.
## The floor below is not counted — a landing stands on it by definition.
func cell_clearance(cell: Vector2i, limit: int = 3) -> int:
	if not has_cell(cell):
		return 0
	var left := 0
	while left < limit and has_cell(cell + Vector2i(-left - 1, 0)) \
			and cell_is_free(cell + Vector2i(-left - 1, 0)):
		left += 1
	var right := 0
	while right < limit and has_cell(cell + Vector2i(right + 1, 0)) \
			and cell_is_free(cell + Vector2i(right + 1, 0)):
		right += 1
	var up := 0
	while up < limit and has_cell(cell + Vector2i(0, -up - 1)) \
			and cell_is_free(cell + Vector2i(0, -up - 1)):
		up += 1
	return mini(mini(left, right), up)


func _rect_hits(centre: Vector2, size: Vector2, include_one_way: bool) -> bool:
	if _solid.is_empty():
		return false
	var start_x := floori((centre.x - size.x * 0.5) / float(FINE_CELL_SIZE))
	var end_x := floori((centre.x + size.x * 0.5 - 0.001) / float(FINE_CELL_SIZE))
	var start_y := floori((centre.y - size.y * 0.5) / float(FINE_CELL_SIZE))
	var end_y := floori((centre.y + size.y * 0.5 - 0.001) / float(FINE_CELL_SIZE))
	if (
		start_x < fine_rect.position.x
		or start_y < fine_rect.position.y
		or end_x >= fine_rect.end.x
		or end_y >= fine_rect.end.y
	):
		return true
	var stride := fine_rect.size.x
	var origin_x := fine_rect.position.x
	for fy: int in range(start_y, end_y + 1):
		var row := (fy - fine_rect.position.y) * stride
		for fx: int in range(start_x, end_x + 1):
			var index := row + fx - origin_x
			if _solid[index] != 0:
				return true
			if include_one_way and _one_way[index] != 0:
				return true
	return false


func _physics_support(
	space: PhysicsDirectSpaceState2D,
	query: PhysicsShapeQueryParameters2D,
	origin: Vector2
) -> bool:
	# A leftover motion on the shared query makes the next intersect_shape sweep
	# the shape, so restore it after the cast.
	var previous_motion := query.motion
	query.transform = Transform2D(0.0, origin + body_offset)
	query.motion = Vector2(0.0, 2.5)
	var result := space.cast_motion(query)
	query.motion = previous_motion
	return result.size() >= 2 and result[1] < 1.0


func _paint_rects(rects: Array[Rect2]) -> void:
	for rect: Rect2 in rects:
		var start_x := maxi(fine_rect.position.x, floori(rect.position.x / float(FINE_CELL_SIZE)))
		var end_x := mini(
			fine_rect.end.x - 1,
			ceili(rect.end.x / float(FINE_CELL_SIZE)) - 1
		)
		var start_y := maxi(fine_rect.position.y, floori(rect.position.y / float(FINE_CELL_SIZE)))
		var end_y := mini(
			fine_rect.end.y - 1,
			ceili(rect.end.y / float(FINE_CELL_SIZE)) - 1
		)
		for fy: int in range(start_y, end_y + 1):
			for fx: int in range(start_x, end_x + 1):
				_solid[_fine_index(fx, fy)] = 1


func _mark_ladder_cells() -> void:
	if _ladder_rects.is_empty():
		return
	for cy: int in range(nav_rect.position.y, nav_rect.end.y):
		for cx: int in range(nav_rect.position.x, nav_rect.end.x):
			if is_on_ladder(cell_to_world(Vector2i(cx, cy))):
				_ladder[_nav_index(cx, cy)] = 1


func _fine_index(fx: int, fy: int) -> int:
	return (
		(fy - fine_rect.position.y) * fine_rect.size.x
		+ (fx - fine_rect.position.x)
	)


func _nav_index(cx: int, cy: int) -> int:
	return (
		(cy - nav_rect.position.y) * nav_rect.size.x
		+ (cx - nav_rect.position.x)
	)
