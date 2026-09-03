# Player Tuning

The default tuning resource is:

`res://resources/player/default_player_tuning.tres`

Important fields:

- `max_speed`: horizontal run speed in source pixels per second.
- `ground_accel`: acceleration while grounded.
- `ground_decel`: deceleration while grounded.
- `air_accel`: acceleration while airborne.
- `air_decel`: deceleration while airborne.
- `jump_speed`: initial upward jump velocity.
- `gravity`: base gravity.
- `fall_gravity_multiplier`: gravity multiplier while falling.
- `jump_cut_gravity_multiplier`: gravity multiplier when the jump key is released during ascent.
- `fast_fall_multiplier`: extra falling gravity while holding down.
- `max_fall_speed`: terminal downward speed.
- `jump_buffer_time`: how long a jump press is remembered.
- `coyote_time`: how long ground jump remains valid after leaving a ledge.

Movement authority belongs to `_physics_process()`. Keep physics positions and velocities as floats; use viewport scaling, texture settings, and camera rounding for pixel clarity.
