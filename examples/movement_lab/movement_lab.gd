extends Node2D

const ROOM_BOUNDS := Rect2(Vector2.ZERO, Vector2(960.0, 360.0))
const RESPAWN_POSITION := Vector2(40.0, 288.0)

@onready var player: CharacterBody2D = $Player
@onready var camera: Camera2D = $PixelCamera2D
@onready var falling_platform: AnimatableBody2D = $Fixtures/FallingPlatform
@onready var combined_platform: AnimatableBody2D = $Fixtures/CombinedMovingFallingPlatform


func _ready() -> void:
	player.respawn_at(RESPAWN_POSITION)
	camera.bind_target(player)
	camera.set_camera_mode(PixelCamera2D.CameraMode.ROOM_LOCKED)
	camera.set_room_bounds(ROOM_BOUNDS)


func _physics_process(_delta: float) -> void:
	if player.global_position.y > ROOM_BOUNDS.end.y + 80.0:
		_reset_player()


func _reset_player() -> void:
	player.respawn_at(RESPAWN_POSITION)
	falling_platform.reset_platform(Vector2(704.0, 264.0))
	combined_platform.reset_platform(Vector2(824.0, 232.0))
