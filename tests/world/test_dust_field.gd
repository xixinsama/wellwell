extends Node

## DustField: single-pixel foreground dust.
##
## The motes are procedural, so everything here is deterministic: the layout is
## seeded, the positions are integral, and the drift only ever wraps inside the
## room rectangle.

const DUST_FIELD: Script = preload("res://scripts/world/dust_field.gd")
const ROOM_DATA: Script = preload("res://addons/platformer_kit/world/data/room_data.gd")


func run() -> Array[String]:
	var failures: Array[String] = []
	_assert_binding_seeds_the_room(failures)
	_assert_motes_stay_inside_the_room(failures)
	_assert_motes_drift_slowly(failures)
	_assert_layout_is_deterministic(failures)
	_assert_clear_room_stops_the_dust(failures)
	return failures


func _assert_binding_seeds_the_room(failures: Array[String]) -> void:
	var field: Node2D = DUST_FIELD.new() as Node2D
	add_child(field)
	field.set("count", 32)
	if not bool(field.call("bind_room_with_origin", _make_room(), null, Vector2i.ZERO)):
		failures.append("DustField rejected a room")
	if int(field.call("get_mote_count")) != 32:
		failures.append("DustField did not seed the requested mote count")
	var positions: PackedVector2Array = field.call("get_mote_positions")
	if positions.size() != 32:
		failures.append("DustField reported %d mote positions for 32 motes" % positions.size())
	for position: Vector2 in positions:
		if position != position.floor():
			failures.append("a mote is not on the pixel grid (%s)" % str(position))
			break
	field.free()


func _assert_motes_stay_inside_the_room(failures: Array[String]) -> void:
	var field: Node2D = DUST_FIELD.new() as Node2D
	add_child(field)
	field.call("bind_room_with_origin", _make_room(), null, Vector2i(2, 1))
	var rect: Rect2 = field.call("get_room_rect")
	if rect.position != Vector2(640.0, 180.0) or rect.size != Vector2(320.0, 180.0):
		failures.append("DustField built the wrong room rect %s" % str(rect))
	# Drift for a long time: wrapping has to keep every mote inside the rect.
	for step: int in 400:
		field.call("_process", 0.25)
	for position: Vector2 in field.call("get_mote_positions"):
		if not rect.has_point(position):
			failures.append("a mote drifted out of the room rect: %s" % str(position))
			break
	field.free()


func _assert_motes_drift_slowly(failures: Array[String]) -> void:
	var field: Node2D = DUST_FIELD.new() as Node2D
	add_child(field)
	field.call("bind_room_with_origin", _make_room(), null, Vector2i.ZERO)
	var rect: Rect2 = field.call("get_room_rect")
	var before: PackedVector2Array = field.call("get_mote_positions")
	field.call("_process", 1.0)
	var after: PackedVector2Array = field.call("get_mote_positions")
	var moved := 0
	var fastest := 0.0
	for index: int in mini(before.size(), after.size()):
		# Measure in wrapped space: a mote crossing the room edge is teleported by
		# the wrap, which is not motion.
		var dx := absf(after[index].x - before[index].x)
		var dy := absf(after[index].y - before[index].y)
		dx = minf(dx, rect.size.x - dx)
		dy = minf(dy, rect.size.y - dy)
		var delta := Vector2(dx, dy).length()
		if delta >= 1.0:
			moved += 1
		fastest = maxf(fastest, delta)
	if moved == 0:
		failures.append("dust never moved in one second")
	if fastest > 20.0:
		failures.append("dust moved %.1f px in one second, that is not slow" % fastest)
	field.free()


func _assert_layout_is_deterministic(failures: Array[String]) -> void:
	var first: Node2D = DUST_FIELD.new() as Node2D
	add_child(first)
	first.call("bind_room_with_origin", _make_room(), null, Vector2i.ZERO)
	var first_positions: PackedVector2Array = first.call("get_mote_positions")
	first.free()
	var second: Node2D = DUST_FIELD.new() as Node2D
	add_child(second)
	second.call("bind_room_with_origin", _make_room(), null, Vector2i.ZERO)
	var second_positions: PackedVector2Array = second.call("get_mote_positions")
	if first_positions != second_positions:
		failures.append("two fresh rooms seeded different dust for the same seed")
	second.free()


func _assert_clear_room_stops_the_dust(failures: Array[String]) -> void:
	var field: Node2D = DUST_FIELD.new() as Node2D
	add_child(field)
	field.call("bind_room_with_origin", _make_room(), null, Vector2i.ZERO)
	field.call("clear_room")
	if int(field.call("get_mote_count")) != 0:
		failures.append("clear_room kept the room's motes")
	if not (field.call("get_mote_positions") as PackedVector2Array).is_empty():
		failures.append("clear_room kept mote positions")
	field.free()


func _make_room() -> Resource:
	var room: Resource = ROOM_DATA.new()
	room.room_id = "dust_room"
	room.room_size_chunks = Vector2i.ONE
	return room
