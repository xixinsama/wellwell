# Player Tuning

The default tuning resource is:

`res://resources/player/default_player_tuning.tres`

`PlayerTuning` extends `MovementProfile`; every value is expressed per second,
so the same tuning works at 60 Hz and 120 Hz.

## Horizontal

- `max_speed`: horizontal run speed in source pixels per second.
- `ground_acceleration` / `ground_deceleration`: grounded approach rates.
- `air_acceleration` / `air_deceleration`: airborne approach rates.
- `run_reduce`: friction while above `max_speed` and still pushing that way.
- `air_multiplier`: scaling applied to `run_reduce` in the air.

## Jump and Fall

- `jump_speed`: initial jump velocity (`-120` keeps the previous ~32 px jump).
- `jump_h_boost`: horizontal speed added on a running jump.
- `var_jump_time`: how long holding jump clamps the rise.
- `gravity`: base gravity.
- `half_gravity_threshold`: vertical speed below which gravity is halved while
  jump is held.
- `max_fall_speed` / `fast_max_fall_speed`: normal and down-held fall caps.
- `fast_max_accel`: how quickly the fall cap moves between the two values.
- `jump_buffer_time` / `coyote_time`: forgiveness windows in seconds.
- `lift_x_cap` / `lift_y_cap`: caps for inherited moving-platform momentum.

## Dash

The supplied Dash is
`res://addons/platformer_abilities/abilities/dash/default_dash.tres`:

- `dash_speed`: dash velocity; diagonals are normalized.
- `dash_duration`: how long the dash velocity lasts (`0.15`).
- `freeze_seconds`: global hit-stop at dash start (`0.05`).
- `end_speed`: speed kept when the dash expires (`160`).
- `dash_attack_seconds`: super/hyper/wallbounce window (`0.3`).
- `cooldown_seconds`: delay before another dash (`0.2`).
- `refill_cooldown_seconds`: ground-refill suppression after a dash (`0.1`).
- `max_charges`: stored dashes (1 by default).
- `eight_directional`, `direction_deadzone`, `direction_snap_degrees`: input
  shaping.

## Wall and Stamina

Wall movement is unlocked by the `climb` ability
(`addons/platformer_abilities/abilities/climb/default_climb.tres`). Without it,
the player never enters `WALL_GRAB` / `WALL_SLIDE`, so grab, climb, wall slide,
wall jump and wallbounce are all disabled together.
- `wall_check_distance`: horizontal wall probe (`3 px`).
- `wallbounce_check_distance`: wider wallbounce probe (`5 px`).
- `wall_jump_speed`: push-away speed (`130`).
- `wall_jump_force_time`: forced horizontal input lock (`0.16 s`).
- `wall_grab_lockout`: auto-grab lock after a wall jump (`0.16 s`).
- `wall_climb_speed` / `climb_down_speed`: wall climb rates (`45` / `80`).
- `climb_speed`: ladder speed, kept separate at `72`.
- `wall_slide_start_speed` / `wall_slide_time`: wall slide cap (`20 -> 160`
  over `1.2 s`).
- `max_stamina`, `stamina_grab_drain`, `stamina_climb_drain`,
  `stamina_tired_threshold`, `climb_jump_stamina`,
  `climb_jump_convert_time`: stamina economy.

## Celeste Momentum (optional)

The Game setting `celeste_momentum_enabled` is **off by default**. When it is
on, two extra rules are enabled:

- A dash keeps the pre-dash horizontal speed when it is larger than the dash
  speed and points in the same direction.
- A down-diagonal dash that touches the ground applies the Ultra `x1.2`
  multiplier, zeroes vertical speed, and finishes the dash. This allows
  chained ultras to exceed the normal 325 px/s hyper exit speed.

Turn it on in Settings → Game → Celeste Momentum. It applies live to the
player controller.

## Advanced Jumps

- `super_jump_speed`: horizontal dash + jump (`260`).
- `hyper_jump_speed` / `hyper_jump_vertical`: ducking dash + jump
  (`325`, `-60`).
- `wallbounce_speed` / `wallbounce_jump_speed`: up-dash wallbounce
  (`170`, `-160`).
- `dash_attack_time`: how long a dash can still convert into these jumps.

Movement authority belongs to `_physics_process()`. Keep physics positions and
velocities as floats; use viewport scaling, texture settings, and camera
rounding for pixel clarity.
