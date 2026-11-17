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

## Dash

The supplied Dash is `res://addons/platformer_abilities/abilities/dash/default_dash.tres`
(a `DashAbilityDefinition`):

- `dash_speed`: dash velocity in source pixels per second (diagonals keep the same
  speed because the direction is normalized).
- `dash_duration`: how long the velocity override lasts.
- `cooldown_seconds`: delay before the next dash.
- `eight_directional`: read the vertical input as well; off keeps the legacy
  horizontal-only dash.
- `max_charges`: stored dashes before a refill (1 = one dash per landing, 0 =
  unlimited). The player controller refills while grounded and while swimming;
  the water refill runs every frame, which makes dashes unlimited there.
- `direction_deadzone`: input shorter than this falls back to the facing direction.
- `direction_snap_degrees`: snap the dash to this angle step (45 keeps the eight
  directions crisp; 0 disables snapping).

Crossing a one-way platform is a game rule, not a Dash resource value:
`game/player/one_way_dash_piercer.gd` activates only for cardinal dashes that
travel in the direction the platform blocks.
