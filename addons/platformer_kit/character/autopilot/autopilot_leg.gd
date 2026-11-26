class_name AutopilotLeg
extends RefCounted

## One planned movement step: a compact per-tick input script plus the trajectory
## the solver expects the character to follow. The driver replays the script and
## compares the live position with [member samples] to catch drift.

const MODE_GROUND := 0
const MODE_AIR := 1
const MODE_WALL_LEFT := 2
const MODE_WALL_RIGHT := 3
const MODE_LADDER := 4

const DASH_NONE := 255
const DASH_DIRECTIONS: Array[Vector2] = [
	Vector2(1.0, 0.0),
	Vector2(0.7071, 0.7071),
	Vector2(0.0, 1.0),
	Vector2(-0.7071, 0.7071),
	Vector2(-1.0, 0.0),
	Vector2(-0.7071, -0.7071),
	Vector2(0.0, -1.0),
	Vector2(0.7071, -0.7071),
]

var action: StringName = &""
var start_cell := Vector2i.ZERO
var end_cell := Vector2i.ZERO
var start_mode := MODE_GROUND
var end_mode := MODE_GROUND
var start_position := Vector2.ZERO
var end_position := Vector2.ZERO
var start_velocity := Vector2.ZERO
var end_velocity := Vector2.ZERO
var frames := 0
var dash_charge_after := true
var stamina_after := 110.0
## Four bytes per tick: axis, vertical, flags, dash direction index.
var intents := PackedByteArray()
var samples := PackedVector2Array()


static func wall_side_for_mode(mode: int) -> int:
	if mode == MODE_WALL_LEFT:
		return -1
	if mode == MODE_WALL_RIGHT:
		return 1
	return 0


func get_frame_count() -> int:
	return frames


## Decoded intent for [param tick]; ticks past the end return neutral input.
func get_intent(tick: int) -> Dictionary:
	var base := tick * 4
	if base < 0 or base + 3 >= intents.size():
		return {
			"axis": 0.0,
			"vertical": 0.0,
			"jump_pressed": false,
			"jump_held": false,
			"dash_dir": Vector2.ZERO,
		}
	var flags := intents[base + 2]
	var dash_index := intents[base + 3]
	return {
		"axis": float(intents[base] - 1),
		"vertical": float(intents[base + 1] - 1),
		"jump_pressed": (flags & 1) != 0,
		"jump_held": (flags & 2) != 0,
		"dash_dir": (
			DASH_DIRECTIONS[dash_index] if dash_index < DASH_DIRECTIONS.size() else Vector2.ZERO
		),
	}


func get_sample(tick: int) -> Vector2:
	if samples.is_empty():
		return end_position
	return samples[clampi(tick, 0, samples.size() - 1)]


func action_label() -> String:
	match action:
		&"walk":
			return "走"
		&"fall":
			return "落"
		&"jump":
			return "跳"
		&"dash":
			return "冲刺"
		&"dash_jump":
			return "冲刺跳"
		&"jump_dash":
			return "跳冲"
		&"wall_step":
			return "攀墙"
		&"wall_jump":
			return "登墙跳"
		&"wall_climb_jump":
			return "登墙跳"
		&"ladder":
			return "爬梯"
	return String(action)


## ASCII action code for on-screen text (the engine default font has no CJK).
func action_code() -> String:
	match action:
		&"walk":
			return "RUN"
		&"fall":
			return "DROP"
		&"jump":
			return "JUMP"
		&"dash":
			return "DASH"
		&"dash_jump":
			return "DASH+JUMP"
		&"jump_dash":
			return "JUMP+DASH"
		&"wall_step":
			return "WALL CLIMB"
		&"wall_jump":
			return "WALL JUMP"
		&"wall_climb_jump":
			return "CLIMB JUMP"
		&"ladder":
			return "LADDER"
	return String(action).to_upper()


func action_color() -> Color:
	match action:
		&"walk", &"fall":
			return Color(0.92, 0.95, 0.92, 0.92)
		&"jump":
			return Color(0.42, 0.86, 0.95, 0.95)
		&"dash", &"dash_jump", &"jump_dash":
			return Color(0.98, 0.36, 0.82, 0.95)
		&"wall_step", &"wall_jump", &"wall_climb_jump":
			return Color(0.99, 0.77, 0.28, 0.95)
		&"ladder":
			return Color(0.45, 0.95, 0.52, 0.95)
	return Color.WHITE


func append_tick(
	axis: float,
	vertical: float,
	jump_pressed: bool,
	jump_held: bool,
	dash_dir: Vector2,
	position: Vector2
) -> void:
	var flags := 0
	if jump_pressed:
		flags |= 1
	if jump_held:
		flags |= 2
	var dash_index := DASH_NONE
	if not dash_dir.is_zero_approx():
		dash_index = _dash_index(dash_dir)
		flags |= 4
	intents.append(clampi(roundi(axis), -1, 1) + 1)
	intents.append(clampi(roundi(vertical), -1, 1) + 1)
	intents.append(flags)
	intents.append(dash_index)
	samples.append(position)
	frames += 1


func _dash_index(dash_dir: Vector2) -> int:
	var best := 0
	var best_dot := -INF
	var normalized := dash_dir.normalized()
	for index: int in range(DASH_DIRECTIONS.size()):
		var dot := normalized.dot(DASH_DIRECTIONS[index])
		if dot > best_dot:
			best_dot = dot
			best = index
	return best
