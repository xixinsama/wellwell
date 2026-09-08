class_name PixelCamera2D
extends Camera2D

enum CameraMode { FREE, ROOM_LOCKED }

const CHUNK_SIZE_PIXELS := Vector2(320.0, 180.0)

@export var target_path: NodePath
@export var camera_mode: CameraMode = CameraMode.FREE

var target: Node2D
var smoothed_position := Vector2.ZERO
var shake_frames_remaining := 0
var shake_amplitude := 0.0
var shake_sign := 1
var room_bounds := Rect2()
var room_lock_is_fixed := false
var _target_is_explicitly_bound := false


func _ready() -> void:
	if not _target_is_explicitly_bound and target_path != NodePath():
		target = get_node_or_null(target_path) as Node2D
	if target != null:
		smoothed_position = target.global_position
		global_position = smoothed_position.round()
	make_current()


func bind_target(new_target: Node2D) -> void:
	_target_is_explicitly_bound = true
	target = new_target
	if target != null:
		smoothed_position = target.global_position
		global_position = smoothed_position.round()


func set_camera_mode(mode: CameraMode) -> void:
	camera_mode = mode


func set_room_bounds(bounds: Rect2) -> void:
	room_bounds = bounds
	room_lock_is_fixed = bounds.size.x <= CHUNK_SIZE_PIXELS.x and bounds.size.y <= CHUNK_SIZE_PIXELS.y
	if camera_mode == CameraMode.ROOM_LOCKED:
		var clamped_target := get_room_camera_target(smoothed_position)
		smoothed_position = clamped_target
		global_position = clamped_target.round()


func clear_room_bounds() -> void:
	room_bounds = Rect2()
	room_lock_is_fixed = false


func get_room_camera_target(follow_position: Vector2, viewport_size := Vector2.ZERO) -> Vector2:
	if room_lock_is_fixed:
		return room_bounds.get_center()
	var effective_viewport := viewport_size
	if effective_viewport.is_zero_approx():
		effective_viewport = get_viewport_rect().size / zoom if is_inside_tree() else CHUNK_SIZE_PIXELS
	var half_viewport := effective_viewport * 0.5
	var minimum := room_bounds.position + half_viewport
	var maximum := room_bounds.end - half_viewport
	return Vector2(
		clampf(follow_position.x, minimum.x, maximum.x) if minimum.x <= maximum.x else room_bounds.get_center().x,
		clampf(follow_position.y, minimum.y, maximum.y) if minimum.y <= maximum.y else room_bounds.get_center().y
	)


func _physics_process(delta: float) -> void:
	if not _target_is_explicitly_bound and target == null and target_path != NodePath():
		target = get_node_or_null(target_path) as Node2D
	if target == null:
		return
	var desired_position := target.global_position
	if camera_mode == CameraMode.ROOM_LOCKED and room_bounds.has_area():
		desired_position = get_room_camera_target(desired_position)
	var weight := 1.0 - exp(-position_smoothing_speed * delta)
	smoothed_position = smoothed_position.lerp(desired_position, weight)
	global_position = (smoothed_position + _consume_shake_offset()).round()


func add_shake(frames: int, amplitude: float) -> void:
	shake_frames_remaining = maxi(frames, 0)
	shake_amplitude = maxf(amplitude, 0.0)
	shake_sign = 1


func _consume_shake_offset() -> Vector2:
	if shake_frames_remaining <= 0 or shake_amplitude <= 0.0:
		return Vector2.ZERO
	shake_frames_remaining -= 1
	shake_sign *= -1
	return Vector2(roundf(shake_amplitude) * float(shake_sign), 0.0)
