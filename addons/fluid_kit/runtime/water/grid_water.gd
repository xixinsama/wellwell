class_name GridWater
extends RefCounted

## Conservative 2D water grid: cellular shallow water for a tile platformer.
##
## Every cell is a small tank that fits `cell_pixels` of water height. A step has
## two passes, and both of them only ever move water between two neighbouring
## cells:
##
##   1. gravity  - a cell pours into the cell below while that cell has room
##   2. lateral  - two cells in the same row exchange water in proportion to
##                 their height difference, so a surface levels out
##
## Water never moves upward. A pool therefore levels out and spills over the next
## edge instead of climbing a wall, which is the behaviour a platformer needs.
##
## Volume is conserved exactly. The donor limit (a cell cannot give more than it
## holds) and the receiver limit (it cannot give more than the receiver fits)
## keep every cell inside [0, cell_pixels], so nothing has to be clamped away.
## Solid cells never hold water, which is how a wall inside a filled region
## removes its own volume.
##
## The grid is in cell space; `origin` is the world position of cell (0, 0).

## Height below this is float dust from the transfer passes.
const EPSILON := 1e-5
## A cell never gives more than this share of its water to one lateral
## neighbour. Only two neighbours can pull at once, so the pair of them still
## cannot drain the cell.
const DONOR_SHARE := 0.45
## Two lateral neighbours can feed one cell, so keeping each receiver under this
## share guarantees that a cell never overflows.
const RECEIVER_SHARE := 0.45
## A cell at rest: below this height, and with nothing to give, the grid sleeps.
const REST_HEIGHT := 1e-3
## The grid sleeps when no single transfer moves more than this many pixels in a
## step. Absolute totals are wrong here: a wide, nearly level pool moves a lot of
## water very slowly, and summing the transfers would put it to sleep early.
const SLEEP_TRANSFER := 0.0015

## World position of cell (0, 0).
var origin := Vector2.ZERO
var width := 0
var height := 0
var cell_pixels := 4.0
## Lateral transfer coefficient (1/s) per pixel of height difference. The step is
## stable while lateral_rate * delta stays under 0.5.
var lateral_rate := 24.0
## Share of a cell that pours into the cell below per step: 1 drains a full cell
## in a single step, which is what makes a fall look like a fall.
var fall_rate := 1.0
## Overflow coefficient (1/s) for a full cell that is *backed up* (the cell below
## is full or solid). Such a cell pours over its side at a much higher rate than
## the surface slope alone would give, which is what lets a deep basin drain and a
## filled pool level out in a second or two instead of seeping for a minute. A
## falling cell is not backed up, so a waterfall stays a coherent column.
var overflow_rate := 30.0
## Leveling coefficient (1/s) between the surfaces of two neighbouring columns.
## The row pass alone can only trade water between two cells of the same row, so
## a deep basin would drain at its surface and stay tilted; this pass moves water
## between the surface cells of adjacent columns, which is what keeps a pool flat
## while it fills or drains. It is swept several times per step, so the surface
## equalizes in a frame instead of taking a minute to creep across a wide basin.
var level_rate := 96.0
## Leveling sweeps per step. Leveling is the most expensive pass per column, so this
## is the knob to turn down on a fine grid; `setup` drops it to two sweeps when the
## grid also runs inner steps, which already equalize the surface twice per tick.
var level_sweeps := 3
## How far apart two neighbouring column surfaces may be and still be treated as
## one body. A waterfall is far above the pool it feeds and must not be levelled.
const LEVEL_MAX_ROW_GAP := 2
## Surface difference (px) below which the leveling pass does nothing. Well under
## a pixel, so it only skips pairs that are already level.
const LEVEL_DEADBAND := 0.05
## How many cells the leveling pass may raise a receiving column in one sweep.
const MAX_RISE := 3

var _solid := PackedByteArray()
var _water := PackedFloat32Array()
var _delta := PackedFloat32Array()
## Net lateral displacement of the last step, in px (positive = moving right).
var _flow_x := PackedFloat32Array()
## Downward displacement of the last step, in px (positive = falling).
var _flow_y := PackedFloat32Array()
var _active := false
var _moved_last := 0.0
var _max_transfer := 0.0
var _last_delta := 1.0 / 60.0
## Physics sub-steps per simulation step. A transfer moves water at most one cell,
## and every coefficient is per second, so the model needs a smaller time step on a
## finer grid: a 4 px cell covers half the distance in the same time. `setup` sets
## this from `cell_pixels`, which keeps the fall speed, the spill rate and the
## settling behaviour identical at every resolution instead of needing a different
## set of tuned coefficients per cell size.
var inner_steps := 1
## Transfer coefficients are tuned for 8 px cells at 1/60 s. A transfer of `h` px of
## height in a cell of `cell_pixels` width carries `h * cell_pixels` of area, so a
## narrower cell carries less for the same surface difference: the coefficients are
## multiplied by `8 / cell_pixels` to keep the physical flow (px^2/s) the same at
## every resolution. Per inner step the product `rate * delta` is unchanged, so
## this does not affect stability.
var rate_scale := 1.0
## Topmost wet cell of each column, recomputed every step.
var _tops := PackedInt32Array()
## Scratch list of the cells a lateral transfer wrote, so the apply loop visits
## those instead of clearing and re-walking the whole rect every step.
var _touched := PackedInt32Array()
## Cell rect that can hold water. The passes only walk this rect, so a settled
## pool in the corner of a big room costs almost nothing. It grows whenever a
## transfer writes a cell and shrinks one dry ring per step.
var _bounds := Rect2i()
## Rows and columns whose cells changed since the last texture rebuild. A narrow
## waterfall moves one band of cells, so rebuilding only that band keeps the upload
## cheap even in a big room.
var _dirty_top := -1
var _dirty_bottom := -1
var _dirty_left := 0
var _dirty_right := 0


## Builds the cell layout. `solid` is one byte per cell in row-major order; a
## non-zero byte is a wall, which never holds water.
func setup(cells: Vector2i, size_px: float, solid: PackedByteArray) -> bool:
	width = maxi(cells.x, 0)
	height = maxi(cells.y, 0)
	cell_pixels = maxf(size_px, 1.0)
	var count := width * height
	if count <= 0:
		return false
	_solid = solid.duplicate()
	if _solid.size() != count:
		_solid.resize(count)
		_solid.fill(0)
	_water.resize(count)
	_water.fill(0.0)
	_delta.resize(count)
	_delta.fill(0.0)
	_flow_x.resize(count)
	_flow_x.fill(0.0)
	_flow_y.resize(count)
	_flow_y.fill(0.0)
	_tops.resize(width)
	_tops.fill(-1)
	# An 8 px cell per 1/60 s is the reference speed. A finer grid runs smaller time
	# steps, so water falls, spills and levels at the same rate in px/s.
	inner_steps = clampi(int(round(8.0 / cell_pixels)), 1, 4)
	rate_scale = 8.0 / cell_pixels
	# Inner steps already equalize the surface more often per tick, so a fine grid
	# needs fewer sweeps to reach the same flatness.
	level_sweeps = 3 if inner_steps <= 1 else 2
	_bounds = Rect2i()
	_active = false
	return true


func is_valid() -> bool:
	return width > 0 and height > 0 and _water.size() == width * height


func index_of_cell(cell: Vector2i) -> int:
	if cell.x < 0 or cell.y < 0 or cell.x >= width or cell.y >= height:
		return -1
	return cell.y * width + cell.x


func cell_of_world(world: Vector2) -> Vector2i:
	var local := (world - origin) / cell_pixels
	return Vector2i(floori(local.x), floori(local.y))


func is_solid(cell: Vector2i) -> bool:
	var index := index_of_cell(cell)
	if index < 0:
		return true
	return _solid[index] != 0


func set_solid(cell: Vector2i, value: bool) -> void:
	var index := index_of_cell(cell)
	if index < 0:
		return
	_solid[index] = 1 if value else 0
	if value:
		_water[index] = 0.0
	_touch(index)
	wake()


func get_height_cell(cell: Vector2i) -> float:
	var index := index_of_cell(cell)
	if index < 0 or _solid[index] != 0:
		return 0.0
	return _water[index]


func get_height_at(index: int) -> float:
	if index < 0 or index >= _water.size() or _solid[index] != 0:
		return 0.0
	return _water[index]


func set_height_at(index: int, value: float) -> void:
	if index < 0 or index >= _water.size() or _solid[index] != 0:
		return
	_water[index] = clampf(value, 0.0, cell_pixels)
	if _water[index] > 0.0:
		_touch(index)
	wake()


func is_solid_at(index: int) -> bool:
	if index < 0 or index >= _solid.size():
		return true
	return _solid[index] != 0


## Fills every open cell of `rect` (cell space) to the top. Returns the volume in
## in px^2, so callers can report how much a wall removed.
func fill_rect(rect: Rect2i) -> float:
	var added := 0.0
	var from_x := clampi(rect.position.x, 0, width)
	var to_x := clampi(rect.position.x + rect.size.x, 0, width)
	var from_y := clampi(rect.position.y, 0, height)
	var to_y := clampi(rect.position.y + rect.size.y, 0, height)
	for y in range(from_y, to_y):
		var row := y * width
		for x in range(from_x, to_x):
			var index := row + x
			if _solid[index] != 0:
				continue
			var missing := cell_pixels - _water[index]
			if missing <= 0.0:
				continue
			_water[index] = cell_pixels
			added += missing
	if added > 0.0:
		_touch_rect(Rect2i(from_x, from_y, to_x - from_x, to_y - from_y))
		wake()
	return added * cell_pixels


## Adds `amount` px^2 around `world` with a linear falloff inside `radius`. The
## water is spread only over open cells that still have room; whatever does not
## fit is returned instead of being dropped.
func add_volume(world: Vector2, radius: float, amount: float) -> float:
	if amount <= 0.0 or not is_valid():
		return amount
	var cell := cell_of_world(world)
	var reach := maxi(int(ceil(radius / cell_pixels)), 1)
	var weights: Dictionary[int, float] = {}
	var total := 0.0
	for y in range(cell.y - reach, cell.y + reach + 1):
		for x in range(cell.x - reach, cell.x + reach + 1):
			var index := index_of_cell(Vector2i(x, y))
			if index < 0 or _solid[index] != 0:
				continue
			var centre := origin + (Vector2(x, y) + Vector2(0.5, 0.5)) * cell_pixels
			var distance := centre.distance_to(world)
			if distance > radius:
				continue
			var weight := 1.0 - distance / maxf(radius, 1.0)
			if weight <= 0.0:
				continue
			weights[index] = weight
			total += weight
	if total <= 0.0:
		return amount
	var area := cell_pixels
	var left := amount
	for index: int in weights:
		var share := amount * weights[index] / total
		var missing := (cell_pixels - _water[index]) * area
		var added := minf(share, missing)
		_water[index] += added / area
		left -= added
		if added > 0.0:
			_touch(index)
	wake()
	return maxf(left, 0.0)


## Removes up to `amount` px^2 in a radius and returns what was actually taken.
func remove_volume(world: Vector2, radius: float, amount: float) -> float:
	if amount <= 0.0 or not is_valid():
		return 0.0
	var cell := cell_of_world(world)
	var reach := maxi(int(ceil(radius / cell_pixels)), 1)
	var area := cell_pixels
	var taken := 0.0
	for y in range(cell.y - reach, cell.y + reach + 1):
		for x in range(cell.x - reach, cell.x + reach + 1):
			var index := index_of_cell(Vector2i(x, y))
			if index < 0 or _solid[index] != 0 or _water[index] <= 0.0:
				continue
			var centre := origin + (Vector2(x, y) + Vector2(0.5, 0.5)) * cell_pixels
			if centre.distance_to(world) > radius:
				continue
			var share := minf(amount - taken, _water[index] * area)
			if share <= 0.0:
				continue
			_water[index] -= share / area
			_touch(index)
			taken += share
	if taken > 0.0:
		wake()
	return taken


## Splash: takes volume from the middle and puts it on the rim of `radius`, so
## the total volume is unchanged and the dip fills back in from the neighbours.
## Only water that the rim can actually take is moved.
func splash(world: Vector2, radius: float, depth: float) -> void:
	if depth <= 0.0 or not is_valid():
		return
	var area := cell_pixels
	var cell := cell_of_world(world)
	var reach := maxi(int(ceil(radius / cell_pixels)), 2)
	var centre: Array[int] = []
	var rim: Array[int] = []
	var rim_room := 0.0
	for y in range(cell.y - reach, cell.y + reach + 1):
		for x in range(cell.x - reach, cell.x + reach + 1):
			var index := index_of_cell(Vector2i(x, y))
			if index < 0 or _solid[index] != 0:
				continue
			var centre_pos := origin + (Vector2(x, y) + Vector2(0.5, 0.5)) * cell_pixels
			var distance := centre_pos.distance_to(world)
			if distance <= radius * 0.5:
				if _water[index] > 0.0:
					centre.append(index)
			elif distance <= radius:
				rim.append(index)
				rim_room += (cell_pixels - _water[index]) * area
	if centre.is_empty() or rim.is_empty() or rim_room <= 0.0:
		return
	# Only move as much as the rim can take, so nothing has to be given back.
	var wanted := minf(depth * area, rim_room)
	var taken := 0.0
	for index: int in centre:
		if taken >= wanted:
			break
		var take := minf(wanted - taken, _water[index] * area)
		if take <= 0.0:
			continue
		_water[index] -= take / area
		taken += take
	if taken <= 0.0:
		return
	for index: int in rim:
		var room := (cell_pixels - _water[index]) * area
		if room <= 0.0:
			continue
		_water[index] += taken * (room / rim_room) / area
		_touch(index)
	wake()


func total_height() -> float:
	var sum := 0.0
	for index in _water.size():
		sum += _water[index]
	return sum


func total_volume() -> float:
	return total_height() * cell_pixels


## World y of the local water surface at a cell: the top of the water in that
## cell, walked up while the cells above are full. INF when the cell is dry.
func get_cell_surface_y(index: int) -> float:
	if index < 0 or index >= _water.size() or _solid[index] != 0:
		return INF
	if _water[index] <= REST_HEIGHT:
		return INF
	var cell_y := index / width
	var current := index
	while cell_y > 0:
		var above := current - width
		if _solid[above] != 0:
			break
		if _water[above] < cell_pixels - EPSILON:
			break
		current = above
		cell_y -= 1
	return origin.y + float(cell_y + 1) * cell_pixels - _water[current]


## World y of the water surface under (or at) `world` in its column: the local
## surface when the point is inside water, otherwise the first surface below it.
## INF when the column is dry.
func surface_y_at(world: Vector2) -> float:
	if not is_valid():
		return INF
	var cell := cell_of_world(world)
	cell.x = clampi(cell.x, 0, width - 1)
	cell.y = clampi(cell.y, 0, height - 1)
	var surface := get_cell_surface_y(cell.y * width + cell.x)
	if surface != INF:
		return surface
	for y in range(cell.y + 1, height):
		var index := y * width + cell.x
		if _solid[index] != 0 or _water[index] <= REST_HEIGHT:
			continue
		return get_cell_surface_y(index)
	return INF


func is_water_at(world: Vector2) -> bool:
	var surface := surface_y_at(world)
	return surface != INF and world.y >= surface


## Horizontal water speed in px/s at `world`, from the last step. Positive means
## moving right.
func flow_x_at(world: Vector2) -> float:
	var index := index_of_cell(cell_of_world(world))
	if index < 0:
		return 0.0
	return _flow_x[index] / maxf(_last_delta, 1e-4)


## 0..1 motion of a cell in the last step, used for foam.
func motion_at(index: int) -> float:
	if index < 0 or index >= _flow_x.size() or cell_pixels <= 0.0:
		return 0.0
	return clampf((absf(_flow_x[index]) + _flow_y[index]) / cell_pixels, 0.0, 1.0)


func is_active() -> bool:
	return _active


func get_moved_last_step() -> float:
	return _moved_last


func wake() -> void:
	_active = true


func sleep() -> void:
	_active = false


## Advances the grid by one fixed step: gravity, then lateral flow, then sleep.
func step(delta: float) -> void:
	if not _active or not is_valid():
		return
	var step_delta := clampf(delta, 0.0, 1.0 / 20.0)
	if step_delta <= 0.0:
		return
	_last_delta = step_delta
	_max_transfer = 0.0
	# Smaller time steps on a finer grid: one transfer per inner step can only move
	# water one cell, so this is what makes a 4 px grid as fast as an 8 px one.
	var sub_delta := step_delta / float(inner_steps)
	var moved := 0.0
	for sub_step in inner_steps:
		moved += _fall_pass(sub_step == 0, sub_step == 0)
		moved += _lateral_pass(sub_delta)
		moved += _level_pass(sub_delta)
	_moved_last = moved
	_shrink_bounds()
	if _max_transfer < SLEEP_TRANSFER:
		_active = false


## World y of a cell's local water surface. The leveling pass inlines this; the
## method stays for queries and tests.
func surface_of_cell(index: int) -> float:
	if index < 0 or index >= _water.size():
		return 0.0
	var row := index / width
	return float(row + 1) * cell_pixels - _water[index]


## Pass 2: keep neighbouring column surfaces level. Water moves from the higher
## surface to the lower one and rises into the cells above the receiver, so the
## receiver's level climbs by more than one cell height when the difference is
## large. Swept in alternating directions, `LEVEL_SWEEPS` times per step. Total
## volume is unchanged and both ends stay inside [0, cell_pixels].
##
## Inlined from `_level_pair`: this runs a few hundred times per step (three sweeps
## over every column), so a function call per pair was measurable. The cached
## surface cells are only refreshed when a transfer can have invalidated them.
func _level_pass(delta: float) -> float:
	if _tops.is_empty() or _bounds.size.x <= 0:
		return 0.0
	var capacity := cell_pixels
	var sub_delta := level_rate * rate_scale * delta / float(level_sweeps)
	var first := maxi(_bounds.position.x, 0)
	var last := mini(_bounds.position.x + _bounds.size.x - 1, width - 2)
	if first > last:
		return 0.0
	var water := _water
	var solid := _solid
	var tops := _tops
	var moved := 0.0
	for sweep in level_sweeps:
		var ascending := sweep % 2 == 0
		var column := first if ascending else last
		var stop := last + 1 if ascending else first - 1
		var step := 1 if ascending else -1
		while column != stop:
			var pair_left := column
			column += step
			var top_a := tops[pair_left]
			var top_b := tops[pair_left + 1]
			if top_a < 0 or top_b < 0:
				continue
			# Only level surfaces that sit next to each other. A waterfall is many
			# cells above the pool it feeds, and moving water sideways out of its
			# top would thin the fall from above instead of letting it land.
			if absi(top_a / width - top_b / width) > LEVEL_MAX_ROW_GAP:
				continue
			var surface_a := float(top_a / width + 1) * capacity - water[top_a]
			var surface_b := float(top_b / width + 1) * capacity - water[top_b]
			var difference := surface_a - surface_b
			if absf(difference) <= LEVEL_DEADBAND:
				continue
			# difference > 0 means column a holds its surface lower, so b feeds a.
			var a_is_donor := difference < 0.0
			var donor := top_a if a_is_donor else top_b
			var receiver := top_b if a_is_donor else top_a
			var available := water[donor]
			if available <= REST_HEIGHT:
				continue
			var room := _rise_room(receiver)
			if room <= 0.0:
				continue
			var amount := minf(minf(absf(difference) * sub_delta, available * DONOR_SHARE), room)
			if amount <= 0.0:
				continue
			water[donor] -= amount
			_raise_cell(receiver, amount)
			# A transfer only invalidates a cached surface cell when it empties the
			# donor or fills the receiver's top cell.
			if water[donor] <= REST_HEIGHT:
				_refresh_top(pair_left if a_is_donor else pair_left + 1)
			var receiver_column := pair_left + 1 if a_is_donor else pair_left
			var receiver_top := tops[receiver_column]
			if receiver_top >= 0 and water[receiver_top] >= capacity - EPSILON:
				_refresh_top(receiver_column)
			if amount > _max_transfer:
				_max_transfer = amount
			moved += amount
	return moved


## Keeps a column's cached surface cell in step with the cell heights: it climbs
## when the leveling pass filled the cells above it and walks down when it drains.
func _refresh_top(column: int) -> void:
	var top := _tops[column]
	if top < 0:
		return
	while top - width >= 0 and _solid[top - width] == 0 and _water[top - width] > REST_HEIGHT:
		top -= width
	while _water[top] <= REST_HEIGHT:
		var below := top + width
		if below >= _water.size() or _solid[below] != 0:
			top = -1
			break
		top = below
	_tops[column] = top


## Free space a column can take from above its surface, up to MAX_RISE cells.
func _rise_room(receiver: int) -> float:
	var capacity := cell_pixels
	var room := 0.0
	var cell := receiver
	for _step in MAX_RISE:
		if cell < 0 or _solid[cell] != 0:
			break
		room += capacity - _water[cell]
		if _water[cell] < capacity - EPSILON:
			break
		cell -= width
	return room


## Pours `amount` into a column from its surface upwards.
func _raise_cell(receiver: int, amount: float) -> void:
	var capacity := cell_pixels
	var left := amount
	var cell := receiver
	for _step in MAX_RISE:
		if left <= 0.0 or cell < 0 or _solid[cell] != 0:
			break
		var room := capacity - _water[cell]
		if room <= 0.0:
			cell -= width
			continue
		var put := minf(left, room)
		_water[cell] += put
		left -= put
		_touch(cell)
		if left <= 0.0:
			break
		cell -= width


## Cells the passes have to visit: the wet area plus one cell of reach.
func _pass_rect() -> Rect2i:
	if _bounds.size.x <= 0 or _bounds.size.y <= 0:
		return Rect2i()
	var grown := _bounds.grow(1)
	return grown.intersection(Rect2i(0, 0, width, height))


## Grows the wet area to include a cell and one cell of margin, so a transfer can
## always write its receiver, and remembers that the cell's row changed. Kept to
## plain int comparisons: it runs on every transfer of every step.
func _touch(index: int) -> void:
	if index < 0 or index >= _water.size():
		return
	var column := index % width
	var row := index / width
	if _dirty_top < 0:
		_dirty_top = row
		_dirty_bottom = row
		_dirty_left = column
		_dirty_right = column
	else:
		_dirty_top = mini(_dirty_top, row)
		_dirty_bottom = maxi(_dirty_bottom, row)
		_dirty_left = mini(_dirty_left, column)
		_dirty_right = maxi(_dirty_right, column)
	if _bounds.size.x <= 0 or _bounds.size.y <= 0:
		_bounds = Rect2i(column, row, 1, 1)
		return
	var left := _bounds.position.x
	var top := _bounds.position.y
	var right := left + _bounds.size.x
	var bottom := top + _bounds.size.y
	if column - 1 >= left and column + 1 < right and row - 1 >= top and row + 1 < bottom:
		return
	left = mini(left, maxi(column - 1, 0))
	top = mini(top, maxi(row - 1, 0))
	right = maxi(right, mini(column + 2, width))
	bottom = maxi(bottom, mini(row + 2, height))
	_bounds = Rect2i(left, top, right - left, bottom - top)


func _touch_rect(rect: Rect2i) -> void:
	var clipped := rect.intersection(Rect2i(0, 0, width, height))
	if clipped.size.x <= 0 or clipped.size.y <= 0:
		return
	if _dirty_top < 0:
		_dirty_top = clipped.position.y
		_dirty_bottom = clipped.position.y + clipped.size.y - 1
		_dirty_left = clipped.position.x
		_dirty_right = clipped.position.x + clipped.size.x - 1
	else:
		_dirty_top = mini(_dirty_top, clipped.position.y)
		_dirty_bottom = maxi(_dirty_bottom, clipped.position.y + clipped.size.y - 1)
		_dirty_left = mini(_dirty_left, clipped.position.x)
		_dirty_right = maxi(_dirty_right, clipped.position.x + clipped.size.x - 1)
	if _bounds.size.x <= 0 or _bounds.size.y <= 0:
		_bounds = clipped
		return
	_bounds = _bounds.merge(clipped)


## One dry ring per step: a pool that drains back into its basin shrinks its
## working rect instead of walking the whole room forever.
func _shrink_bounds() -> void:
	if _bounds.size.x <= 0 or _bounds.size.y <= 0:
		return
	var top := _bounds.position.y
	var bottom := _bounds.position.y + _bounds.size.y - 1
	if _bounds.size.y > 1 and _row_dry(top):
		_bounds.position.y = top + 1
		_bounds.size.y -= 1
	elif _bounds.size.y > 1 and _row_dry(bottom):
		_bounds.size.y -= 1
	var left := _bounds.position.x
	var right := _bounds.position.x + _bounds.size.x - 1
	if _bounds.size.x > 1 and _column_dry(left):
		_bounds.position.x = left + 1
		_bounds.size.x -= 1
	elif _bounds.size.x > 1 and _column_dry(right):
		_bounds.size.x -= 1


func _row_dry(row: int) -> bool:
	var base := row * width
	for column in _bounds.size.x:
		var index := base + _bounds.position.x + column
		if _water[index] > REST_HEIGHT:
			return false
	return true


func _column_dry(column: int) -> bool:
	for row in _bounds.size.y:
		var index := (_bounds.position.y + row) * width + column
		if _water[index] > REST_HEIGHT:
			return false
	return true


## A cell holds water that is resting on something: the cell below is solid or
## full. Water mid-fall is not supported, which is what keeps a waterfall a
## column instead of a spreading sheet. The passes inline this test; the method
## stays for queries and tests.
func is_supported(index: int) -> bool:
	var below := index + width
	if below >= _water.size():
		return true
	return _solid[below] != 0 or _water[below] >= cell_pixels - EPSILON


## A full, supported cell can pour over its side at the overflow rate.
func is_overflowing(index: int) -> bool:
	if _water[index] < cell_pixels - EPSILON:
		return false
	return is_supported(index)


## Pass 1: gravity. Each cell gives to the cell below while that one has room, one
## cell per sub-step, so a fall is a visible falling column instead of water
## teleporting to the floor.
##
## The scan runs bottom-up and applies each transfer immediately: the receiver row
## has already been visited, so no parcel can move twice in one sub-step and no
## scratch array or extra traversal is needed. `clear` resets the motion arrays and
## the cached surface cells (first sub-step only) and `last` caches the surface
## cells afterwards, so a multi-sub-step fall still clears and caches once.
func _fall_pass(clear: bool, last: bool) -> float:
	var rect := _pass_rect()
	if rect.size.x <= 0 or rect.size.y <= 0:
		return 0.0
	var capacity := cell_pixels
	var limit := capacity * fall_rate
	var moved := 0.0
	var from_x := rect.position.x
	var to_x := rect.position.x + rect.size.x
	var first_row := rect.position.y
	var last_row := mini(rect.position.y + rect.size.y, height)
	if clear:
		for row in range(first_row, last_row):
			var base := row * width
			for column in range(from_x, to_x):
				_flow_y[base + column] = 0.0
				_flow_x[base + column] = 0.0
		for column in range(from_x, to_x):
			_tops[column] = -1
	for row in range(last_row - 2, first_row - 1, -1):
		var base := row * width
		var below_base := base + width
		for column in range(from_x, to_x):
			var index := base + column
			var amount := _water[index]
			if amount <= 0.0:
				continue
			var below := below_base + column
			if _solid[below] != 0:
				continue
			var free := capacity - _water[below]
			if free <= 0.0:
				continue
			var give := minf(minf(amount, free), limit)
			if give <= 0.0:
				continue
			_water[index] = amount - give
			_water[below] += give
			_flow_y[below] = maxf(_flow_y[below], give)
			_flow_y[index] = maxf(_flow_y[index], give)
			_touch(below)
			if give > _max_transfer:
				_max_transfer = give
			moved += give
	if last:
		# First wet cell of every column, for the leveling pass.
		for row in range(first_row, last_row):
			var base := row * width
			for column in range(from_x, to_x):
				var index := base + column
				if _tops[column] < 0 and _water[index] > REST_HEIGHT:
					_tops[column] = index
	return moved


## Pass 2: lateral flow inside each row. Transfers are written to a scratch array
## and applied afterwards, so the scan direction cannot bias the result.
##
## Only the cells a transfer wrote are visited again: the scratch delta is cleared
## by the apply loop, so the pass never walks the dry part of the rect. The pair
## checks are inlined (`_supported`, `_overflowing` and `_touch` are all small
## functions called once per pair, and this loop is the hottest one in the model).
func _lateral_pass(delta: float) -> float:
	var rect := _pass_rect()
	if rect.size.x <= 0 or rect.size.y <= 0:
		return 0.0
	var capacity := cell_pixels
	var rate := lateral_rate * rate_scale * delta
	var spill := capacity * overflow_rate * rate_scale * delta
	var moved := 0.0
	var from_x := rect.position.x
	var to_x := rect.position.x + rect.size.x
	var from_y := rect.position.y
	var to_y := rect.position.y + rect.size.y
	_touched.clear()
	var water := _water
	var solid := _solid
	var delta_buffer := _delta
	var flow := _flow_x
	for row in range(from_y, to_y):
		var base := row * width
		for index in range(base + from_x, base + to_x - 1):
			var other := index + 1
			if solid[index] != 0 or solid[other] != 0:
				continue
			var left := water[index]
			var right := water[other]
			var diff := left - right
			if absf(diff) <= EPSILON:
				continue
			# Only standing water spreads sideways: a falling cell must keep its
			# water, or a waterfall fans out into a thin sheet on the way down. The
			# receiver may be in mid-air, which is exactly a spill over an edge. The
			# donor being full and backed up is also what allows a spill at the much
			# higher overflow rate.
			var donor := index if diff > 0.0 else other
			var below := donor + width
			var supported := below >= water.size() or solid[below] != 0 \
					or water[below] >= capacity - EPSILON
			if not supported:
				continue
			var limited := diff * rate
			if water[donor] >= capacity - EPSILON:
				limited = maxf(limited, spill) if diff > 0.0 else minf(limited, -spill)
			if limited > 0.0:
				var give := minf(minf(limited, left * DONOR_SHARE), (capacity - right) * RECEIVER_SHARE)
				if give <= 0.0:
					continue
				delta_buffer[index] -= give
				delta_buffer[other] += give
				flow[index] -= give
				flow[other] += give
				_touched.append(index)
				_touched.append(other)
				if give > _max_transfer:
					_max_transfer = give
				moved += give
			elif limited < 0.0:
				var give_back := minf(minf(-limited, right * DONOR_SHARE), (capacity - left) * RECEIVER_SHARE)
				if give_back <= 0.0:
					continue
				delta_buffer[index] += give_back
				delta_buffer[other] -= give_back
				flow[index] += give_back
				flow[other] -= give_back
				_touched.append(index)
				_touched.append(other)
				if give_back > _max_transfer:
					_max_transfer = give_back
				moved += give_back
	for touched_index: int in _touched:
		var change := delta_buffer[touched_index]
		if change == 0.0:
			continue
		delta_buffer[touched_index] = 0.0
		water[touched_index] = clampf(water[touched_index] + change, 0.0, capacity)
		_touch(touched_index)
	return moved


## Cells that can hold water right now, plus one cell of margin. The renderer uses
## it to touch only the part of the texture that can have changed.
func wet_bounds() -> Rect2i:
	if _bounds.size.x <= 0 or _bounds.size.y <= 0:
		return Rect2i()
	return _bounds.grow(1).intersection(Rect2i(0, 0, width, height))


## Cells whose texture changed since the last call. This is what the renderer
## rebuilds: a narrow waterfall moves one band of cells, not the whole pool, so the
## upload stays cheap in a large room. Empty when nothing moved.
func take_dirty_bounds() -> Rect2i:
	if _dirty_top < 0:
		return Rect2i()
	var rect := Rect2i(
		_dirty_left,
		_dirty_top,
		_dirty_right - _dirty_left + 1,
		_dirty_bottom - _dirty_top + 1
	)
	_dirty_top = -1
	_dirty_bottom = -1
	# One cell of margin: the shader reads the cell above, below and beside for its
	# edges, and a cell that just went dry has to be cleared.
	return rect.grow(1).intersection(Rect2i(0, 0, width, height))


## Marks the whole grid dirty: used after a fill, a gate change or a resize.
func mark_all_dirty() -> void:
	_dirty_top = 0
	_dirty_bottom = height - 1
	_dirty_left = 0
	_dirty_right = width - 1


## Writes the render texture for `rect` into `bytes`, an RGBA8 buffer of the whole
## grid (row-major, `width` texels per row).
##
##   R = fill of the cell, G = water depth above it, B = motion, A = 255 water.
##
## Cells without water are left as they are (0 = draw nothing). With `with_solid`
## the walls of the rect are written as A = 64: the shader mirrors the surface at a
## wall instead of tapering into it, and the wall mask never changes, so only the
## first build has to write it.
##
## Direct array access with no per-cell calls, because this is the hot path of the
## upload: the caller rebuilds only the wet rect, so a fine grid costs about the
## same as a coarse one.
func write_cell_texture(
	bytes: PackedByteArray, rect: Rect2i, depth_scale: float, with_solid: bool = false
) -> void:
	var inv_capacity := 255.0 / maxf(cell_pixels, 0.001)
	var inv_depth := 255.0 / maxf(depth_scale, 0.001)
	var inv_cell := 1.0 / maxf(cell_pixels, 0.001)
	var from_x := maxi(rect.position.x, 0)
	var to_x := mini(rect.position.x + rect.size.x, width)
	var from_y := maxi(rect.position.y, 0)
	var to_y := mini(rect.position.y + rect.size.y, height)
	for x in range(from_x, to_x):
		var above := 0.0
		for y in range(from_y, to_y):
			var index := y * width + x
			var offset := index * 4
			if _solid[index] != 0:
				if with_solid:
					bytes[offset] = 0
					bytes[offset + 1] = 0
					bytes[offset + 2] = 0
					bytes[offset + 3] = 64
				above = 0.0
				continue
			if _water[index] <= REST_HEIGHT:
				bytes[offset] = 0
				bytes[offset + 1] = 0
				bytes[offset + 2] = 0
				bytes[offset + 3] = 0
				above = 0.0
				continue
			var water := _water[index]
			bytes[offset] = int(clampf(water * inv_capacity, 0.0, 255.0))
			bytes[offset + 1] = int(clampf(above * inv_depth, 0.0, 255.0))
			bytes[offset + 2] = int(
				clampf((absf(_flow_x[index]) + _flow_y[index]) * inv_cell, 0.0, 1.0) * 255.0
			)
			bytes[offset + 3] = 255
			above += water


func get_debug_state() -> Dictionary:
	return {
		"cells": width * height,
		"grid": Vector2i(width, height),
		"cell_pixels": cell_pixels,
		"volume": total_volume(),
		"active": _active,
		"moved": _moved_last,
	}
