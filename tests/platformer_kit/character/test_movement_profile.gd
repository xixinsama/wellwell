extends Node

const PROFILE_SCRIPT_PATH := "res://addons/platformer_kit/character/resources/movement_profile.gd"
const DEFAULT_PROFILE_PATH := "res://addons/platformer_kit/character/resources/default_movement_profile.tres"

const EXPECTED_VALUES := {
	"max_speed": 100.0,
	"ground_acceleration": 850.0,
	"ground_deceleration": 1100.0,
	"air_acceleration": 600.0,
	"air_deceleration": 500.0,
	"jump_speed": -220.0,
	"gravity": 760.0,
	"fall_gravity_multiplier": 1.15,
	"jump_cut_gravity_multiplier": 1.75,
	"fast_fall_multiplier": 1.45,
	"max_fall_speed": 300.0,
	"jump_buffer_time": 0.075,
	"coyote_time": 0.085,
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
		if not is_equal_approx(float(profile.get(property_name)), float(EXPECTED_VALUES[property_name])):
			failures.append("default MovementProfile changed current value: %s" % property_name)
	return failures
