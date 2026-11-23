extends Node

const PROFILE_SCRIPT_PATH := "res://addons/platformer_kit/character/resources/movement_profile.gd"
const DEFAULT_PROFILE_PATH := "res://addons/platformer_kit/character/resources/default_movement_profile.tres"

const EXPECTED_VALUES := {
	"max_speed": 100.0,
	"ground_acceleration": 1000.0,
	"ground_deceleration": 1000.0,
	"air_acceleration": 650.0,
	"air_deceleration": 650.0,
	"run_reduce": 400.0,
	"air_multiplier": 0.65,
	"jump_speed": -120.0,
	"jump_h_boost": 40.0,
	"var_jump_time": 0.2,
	"gravity": 900.0,
	"half_gravity_threshold": 40.0,
	"max_fall_speed": 160.0,
	"fast_max_fall_speed": 240.0,
	"fast_max_accel": 300.0,
	"jump_buffer_time": 0.08,
	"coyote_time": 0.1,
	"climb_speed": 72.0,
	"wall_climb_speed": 45.0,
	"climb_down_speed": 80.0,
	"wall_jump_speed": 130.0,
	"wall_jump_force_time": 0.16,
	"wall_grab_lockout": 0.16,
	"wall_check_distance": 3.0,
	"wallbounce_check_distance": 5.0,
	"wallbounce_speed": 170.0,
	"wallbounce_jump_speed": -160.0,
	"wall_slide_start_speed": 20.0,
	"wall_slide_time": 1.2,
	"climb_jump_stamina": 27.5,
	"climb_jump_convert_time": 0.2,
	"max_stamina": 110.0,
	"stamina_grab_drain": 10.0,
	"stamina_climb_drain": 45.4545,
	"stamina_tired_threshold": 20.0,
	"dash_attack_time": 0.3,
	"super_jump_speed": 260.0,
	"hyper_jump_speed": 325.0,
	"hyper_jump_vertical": -60.0,
	"corner_correction": 4.0,
	"lift_x_cap": 250.0,
	"lift_y_cap": -130.0,
}


func run() -> Array[String]:
	if not ResourceLoader.exists(PROFILE_SCRIPT_PATH, "Script"):
		return ["MovementProfile script is missing"]
	if not ResourceLoader.exists(DEFAULT_PROFILE_PATH, "Resource"):
		return ["default MovementProfile resource is missing"]
	var failures: Array[String] = []
	var profile := ResourceLoader.load(DEFAULT_PROFILE_PATH, "Resource", ResourceLoader.CACHE_MODE_IGNORE)
	if profile == null:
		return ["default MovementProfile resource could not be loaded"]
	for property_name: String in EXPECTED_VALUES:
		if not property_name in profile:
			failures.append("MovementProfile is missing expected value: %s" % property_name)
			continue
		if not is_equal_approx(float(profile.get(property_name)), float(EXPECTED_VALUES[property_name])):
			failures.append("default MovementProfile changed current value: %s" % property_name)
	return failures
