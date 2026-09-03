extends Resource
class_name PlayerTuning

@export var max_speed: float = 100.0
@export var ground_accel: float = 850.0
@export var ground_decel: float = 1100.0
@export var air_accel: float = 600.0
@export var air_decel: float = 500.0
@export var jump_speed: float = -220.0
@export var gravity: float = 760.0
@export var fall_gravity_multiplier: float = 1.15
@export var jump_cut_gravity_multiplier: float = 1.75
@export var fast_fall_multiplier: float = 1.45
@export var max_fall_speed: float = 300.0
@export var jump_buffer_time: float = 0.075
@export var coyote_time: float = 0.085
