class_name MovementProfile
extends Resource

## Celeste-shaped movement rules. Values are per-second so the same profile
## works at 60 Hz and 120 Hz; pixel probes stay in pixels.

# Horizontal control.
@export var max_speed := 100.0
@export var ground_acceleration := 1000.0
@export var ground_deceleration := 1000.0
@export var air_acceleration := 650.0
@export var air_deceleration := 650.0
## Friction used while above max speed and still pushing in that direction.
@export var run_reduce := 400.0
## Air control scaling applied to the over-speed friction only. The air
## acceleration/deceleration values above are already scaled.
@export var air_multiplier := 0.65

# Jump and fall.
@export var jump_speed := -120.0
@export var jump_h_boost := 40.0
@export var var_jump_time := 0.2
@export var gravity := 900.0
@export var half_gravity_threshold := 40.0
@export var max_fall_speed := 160.0
@export var fast_max_fall_speed := 240.0
@export var fast_max_accel := 300.0
@export var jump_buffer_time := 0.08
@export var coyote_time := 0.1

# Wall movement and stamina. Ladder climbing keeps its own speed.
@export var climb_speed := 72.0
@export var wall_climb_speed := 45.0
@export var climb_down_speed := 80.0
@export var wall_jump_speed := 130.0
@export var wall_jump_force_time := 0.16
@export var wall_grab_lockout := 0.16
@export var wall_check_distance := 3.0
@export var wallbounce_check_distance := 5.0
@export var wallbounce_speed := 170.0
@export var wallbounce_jump_speed := -160.0
@export var wall_slide_start_speed := 20.0
@export var wall_slide_time := 1.2
@export var climb_jump_stamina := 27.5
@export var climb_jump_convert_time := 0.2
@export var max_stamina := 110.0
@export var stamina_grab_drain := 10.0
@export var stamina_climb_drain := 45.4545
@export var stamina_tired_threshold := 20.0

# Dash and advanced jump rules.
@export var dash_attack_time := 0.3
@export var super_jump_speed := 260.0
@export var hyper_jump_speed := 325.0
@export var hyper_jump_vertical := -60.0
@export var corner_correction := 4.0
@export var lift_x_cap := 250.0
@export var lift_y_cap := -130.0
