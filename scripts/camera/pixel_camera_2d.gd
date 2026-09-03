extends Camera2D
class_name PixelCamera2D

@export var target_path: NodePath
@export var follow_speed: float = 14.0
@export var safe_size: Vector2 = Vector2(320.0, 180.0)

var target: Node2D
var smoothed_position: Vector2 = Vector2.ZERO
var shake_frames_remaining: int = 0
var shake_amplitude: float = 0.0
var shake_sign: int = 1


func _ready() -> void:
	if target_path != NodePath():
		target = get_node_or_null(target_path) as Node2D
	if target:
		smoothed_position = target.global_position
		global_position = smoothed_position.round()
	make_current()


func _physics_process(delta: float) -> void:
	if target == null and target_path != NodePath():
		target = get_node_or_null(target_path) as Node2D
	if target == null:
		return

	var weight: float = 1.0 - exp(-follow_speed * delta)
	smoothed_position = smoothed_position.lerp(target.global_position, weight)
	var shake_offset: Vector2 = _consume_shake_offset()
	global_position = (smoothed_position + shake_offset).round()


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
