extends RefCounted
## The solver benchmark: one room per test point, two waypoints per room.
##
## Each room lists the abilities the character is allowed to use there, the frame
## budget it has to finish inside, and its terrain as rectangles on a 40 x 23
## cell grid (the same footprint as a shipped room). [method render] turns a spec
## into the rows that [method AutopilotGrid.build_from_rows] consumes, so the
## benchmark grades the same raster the game builds from live collision.

const WIDTH := 40
const HEIGHT := 23
## Rows of solid floor under the playfield.
const FLOOR_ROW := 20


static func specs() -> Array[Dictionary]:
	var rooms: Array[Dictionary] = []
	rooms.append({
		"id": "flat",
		"title": "walk one screen",
		"start": Vector2i(2, 19),
		"goal": Vector2i(37, 19),
		"seconds": 6.0,
		"dash": false,
		"climb": false,
		"solid": [Rect2i(0, FLOOR_ROW, 40, 3)],
	})
	rooms.append({
		"id": "steps",
		"title": "three one-cell steps",
		"start": Vector2i(2, 19),
		"goal": Vector2i(37, 17),
		"seconds": 9.0,
		"dash": false,
		"climb": false,
		"solid": [
			Rect2i(0, FLOOR_ROW, 40, 3),
			Rect2i(12, 19, 2, 1),
			Rect2i(20, 18, 2, 1),
			Rect2i(28, 17, 2, 1),
		],
	})
	rooms.append({
		"id": "one_way_up",
		"title": "jump up through one-way platforms",
		"start": Vector2i(4, 19),
		"goal": Vector2i(14, 14),
		"seconds": 9.0,
		"dash": false,
		"climb": false,
		"solid": [Rect2i(0, FLOOR_ROW, 40, 3)],
		"one_way": [Rect2i(10, 18, 8, 1), Rect2i(10, 15, 8, 1)],
	})
	rooms.append({
		"id": "ladder",
		"title": "climb a ladder",
		"start": Vector2i(4, 19),
		"goal": Vector2i(24, 7),
		"seconds": 11.0,
		"dash": false,
		"climb": false,
		"solid": [Rect2i(0, FLOOR_ROW, 40, 3), Rect2i(21, 7, 12, 1)],
		"ladder": [Rect2i(20, 6, 1, 15)],
	})
	rooms.append({
		"id": "gap_run",
		"title": "running jump over a gap",
		"start": Vector2i(2, 19),
		"goal": Vector2i(35, 19),
		"seconds": 9.0,
		"dash": false,
		"climb": false,
		"solid": [Rect2i(0, FLOOR_ROW, 17, 3), Rect2i(23, FLOOR_ROW, 17, 3)],
	})
	rooms.append({
		"id": "gap_dash",
		"title": "dash over a wide gap",
		"start": Vector2i(2, 19),
		"goal": Vector2i(33, 19),
		"seconds": 9.0,
		"dash": true,
		"climb": false,
		"solid": [Rect2i(0, FLOOR_ROW, 14, 3), Rect2i(26, FLOOR_ROW, 14, 3)],
	})
	rooms.append({
		"id": "dash_ledge",
		"title": "dash-jump onto a high ledge",
		"start": Vector2i(2, 19),
		"goal": Vector2i(26, 13),
		"seconds": 10.0,
		"dash": true,
		"climb": false,
		"solid": [
			Rect2i(0, FLOOR_ROW, 22, 3),
			Rect2i(24, 14, 8, 1),
		],
	})
	rooms.append({
		"id": "climb_shaft",
		"title": "climb a shaft",
		"start": Vector2i(4, 19),
		"goal": Vector2i(18, 8),
		"seconds": 11.0,
		"dash": false,
		"climb": true,
		"solid": [
			Rect2i(0, FLOOR_ROW, 40, 3),
			Rect2i(18, 8, 1, 12),
			Rect2i(22, 8, 1, 12),
		],
	})
	rooms.append({
		"id": "wall_jump",
		"title": "wall jump up a well",
		"start": Vector2i(15, 19),
		"goal": Vector2i(12, 8),
		"seconds": 12.0,
		"dash": false,
		"climb": true,
		"solid": [
			Rect2i(0, FLOOR_ROW, 40, 3),
			Rect2i(11, 8, 2, 12),
			Rect2i(19, 8, 2, 12),
		],
	})
	rooms.append({
		"id": "no_climb",
		"title": "tower without climbing: hop the ledges",
		"start": Vector2i(4, 19),
		"goal": Vector2i(20, 7),
		"seconds": 14.0,
		"dash": false,
		"climb": false,
		"solid": [
			Rect2i(0, FLOOR_ROW, 40, 3),
			Rect2i(8, 17, 4, 1),
			Rect2i(13, 14, 4, 1),
			Rect2i(18, 11, 4, 1),
			Rect2i(18, 7, 8, 1),
		],
	})
	rooms.append({
		"id": "one_way_slot",
		"title": "dash through a slot under one-way platforms",
		"start": Vector2i(2, 19),
		"goal": Vector2i(35, 19),
		"seconds": 10.0,
		"dash": true,
		"climb": false,
		"solid": [
			Rect2i(0, FLOOR_ROW, 40, 3),
			Rect2i(17, 15, 2, 5),
			Rect2i(17, 19, 2, 1),
		],
		"one_way": [Rect2i(14, 16, 8, 1)],
	})
	rooms.append({
		"id": "low_ceiling",
		"title": "low corridor: short hops only",
		"start": Vector2i(2, 19),
		"goal": Vector2i(35, 18),
		"seconds": 10.0,
		"dash": false,
		"climb": false,
		"solid": [
			Rect2i(0, FLOOR_ROW, 40, 3),
			Rect2i(10, 16, 20, 1),
			Rect2i(14, 19, 2, 1),
			Rect2i(22, 19, 2, 1),
		],
	})
	rooms.append({
		"id": "staircase",
		"title": "six-step staircase",
		"start": Vector2i(2, 19),
		"goal": Vector2i(37, 14),
		"seconds": 12.0,
		"dash": false,
		"climb": false,
		"solid": [
			Rect2i(0, FLOOR_ROW, 40, 3),
			Rect2i(8, 19, 3, 1),
			Rect2i(13, 18, 3, 1),
			Rect2i(18, 17, 3, 1),
			Rect2i(23, 16, 3, 1),
			Rect2i(28, 15, 3, 1),
			Rect2i(33, 14, 3, 1),
			Rect2i(36, 14, 4, 1),
		],
	})
	rooms.append({
		"id": "narrow_landings",
		"title": "one-cell landings",
		"start": Vector2i(2, 19),
		"goal": Vector2i(34, 15),
		"seconds": 12.0,
		"dash": false,
		"climb": false,
		"solid": [
			Rect2i(0, FLOOR_ROW, 40, 3),
			Rect2i(10, 17, 1, 1),
			Rect2i(15, 16, 1, 1),
			Rect2i(20, 15, 1, 1),
			Rect2i(25, 16, 1, 1),
			Rect2i(30, 15, 1, 1),
			Rect2i(33, 15, 4, 1),
		],
	})
	rooms.append({
		"id": "mixed",
		"title": "ladder, dash and one-way together",
		"start": Vector2i(2, 19),
		"goal": Vector2i(36, 8),
		"seconds": 14.0,
		"dash": true,
		"climb": true,
		"solid": [
			Rect2i(0, FLOOR_ROW, 40, 3),
			Rect2i(9, 19, 2, 1),
			Rect2i(14, 19, 8, 1),
			Rect2i(26, 8, 10, 1),
			Rect2i(24, 8, 1, 6),
		],
		"one_way": [Rect2i(28, 15, 6, 1)],
		"ladder": [Rect2i(31, 8, 2, 12)],
	})
	rooms.append({
		"id": "stable_choice",
		"title": "tunnel or roof: same cost, prefer the open route",
		"start": Vector2i(4, 19),
		"goal": Vector2i(33, 19),
		"seconds": 12.0,
		"dash": false,
		"climb": false,
		"solid": [
			Rect2i(0, FLOOR_ROW, 40, 3),
			Rect2i(18, 17, 14, 2),
			Rect2i(18, 17, 14, 1),
		],
	})
	return rooms


## Render a spec into rows: `#` solid, `-` one-way, `L` ladder, `.` open.
static func render(spec: Dictionary) -> Array[String]:
	var grid: Array[PackedInt32Array] = []
	for row: int in range(HEIGHT):
		var line := PackedInt32Array()
		line.resize(WIDTH)
		line.fill(0)
		grid.append(line)
	_paint(grid, spec.get("solid", []), 1)
	_paint(grid, spec.get("one_way", []), 2)
	_paint(grid, spec.get("ladder", []), 3)
	var rows: Array[String] = []
	for row: int in range(HEIGHT):
		var text := ""
		for column: int in range(WIDTH):
			match grid[row][column]:
				1:
					text += "#"
				2:
					text += "-"
				3:
					text += "L"
				_:
					text += "."
		rows.append(text)
	return rows


static func _paint(grid: Array[PackedInt32Array], rects: Array, kind: int) -> void:
	for value: Variant in rects:
		var rect: Rect2i = value
		for row: int in range(maxi(rect.position.y, 0), mini(rect.end.y, HEIGHT)):
			for column: int in range(maxi(rect.position.x, 0), mini(rect.end.x, WIDTH)):
				grid[row][column] = kind
