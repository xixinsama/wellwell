# Celeste-Rules Movement Design

Date: 2026-11-22
Status: Approved

## Goal

Reproduce the *rules* that make Celeste movement feel precise while keeping this
project's scale: 6x6 player collision, 8 px tiles, 320x180 rooms, and a
configurable 60 or 120 physics tick rate. The player must not need a grab
button. Existing water, ladder, puzzle, platform, and conveyor systems remain
usable.

This is rule fidelity, not byte-for-byte fidelity. Celeste's 8x11 hitbox and
60 Hz constants are adapted so current rooms keep their jump heights.

## Scope

Implemented:

- Run acceleration, over-speed friction, and air control.
- Variable-height jump with apex half gravity, coyote time, jump buffer.
- Dash freeze, fixed duration, end speed, cooldown, charges, and refill delay.
- Dash-attack state window (0.3 s) with no damage.
- Super, hyper, wavedash, and wallbounce as jump rules, not scripted moves.
- No-grab wall grab, climb, stamina, wall slide, climb jump, wall jump, and
  stamina-refund conversion window.
- Global hit-stop freeze on dash start.
- Platform lift sampling with caps; conveyor carry without jump launch.
- 60/120 Hz compatible timers and tests.

Not implemented:

- A grab input or object grabbing.
- Damage, enemies, or combat hitboxes for dash attack.
- A crouching collision box or demodash.
- A custom actor/solid physics engine. `CharacterBody2D.move_and_slide()`
  remains authoritative.
- Changes to the 6x6 player collision box or existing room geometry.

## Input Mapping Without Grab

Hold toward a wall to attach. The attach state is the grab state.

| Input while touching a wall | Result | Speed and stamina |
| --- | --- | --- |
| Hold toward wall | Grab / hold | `v = 0`; -10 stamina/s |
| Toward + up | Climb up | `v.y = -45`; -45.45 stamina/s |
| Toward + down | Climb down | `v.y = +80`; no stamina cost |
| Toward + jump | Wall jump away | `v = (±130, jump_speed)`; no stamina |
| Toward + up + jump | Climb jump | `v.y = jump_speed`; -27.5 stamina |
| Away/neutral + jump | Wall jump | `v = (±130, jump_speed)`; no stamina |
| Climb jump, then away within 0.2 s | Convert to wall jump | `v.x = ±130`; refund 27.5 |
| Up-dash + wall + jump during dash attack | Wallbounce | `v = (±170, -160)` |
| Ground horizontal dash + jump | Super | `v.x = ±260` |
| Down-diagonal dash into ground + jump | Hyper / wavedash | `v = (±325, -60)` |

Rules:

- Attaching snaps the body flush to the wall, including the side of a moving
  platform. A moving wall carries the player while attached.
- A wall jump applies a 0.16 s forced horizontal velocity and a 0.16 s
  auto-grab lockout **on the wall that was just left only**. The opposite wall
  can be grabbed immediately, which is what makes left/right chains smooth.
- A climb jump deducts 27.5 stamina immediately. If the player presses away
  within 0.2 s, the jump converts to a wall jump and refunds the stamina.
- Tired threshold is 20 stamina. A tired player cannot start a new grab but may
  continue an existing grab. At zero stamina the wall state becomes a slide.
- Wall slide exists only when the player holds toward the wall but cannot grab
  (tired or empty). It has no separate key.

## State Machine

States are mutually exclusive; super/hyper/wavedash/wallbounce are jump
branches, not states.

```text
NORMAL
DASH
WALL_GRAB
WALL_SLIDE
SWIM
LADDER
HURT
```

Priority:

```text
freeze / hurt
> DASH
> SWIM / LADDER
> WALL_GRAB / WALL_SLIDE
> NORMAL
```

`CharacterMotor2D` remains the NORMAL-state physics. New dash and wall logic
live in player-side state helpers so Platformer Kit does not own stamina or the
player's full state graph.

## Tuning

Initial values, exposed through `MovementProfile` / `PlayerTuning`:

| Rule | Value |
| --- | --- |
| max_speed | 100 |
| ground_acceleration / deceleration | 1000 / 1000 |
| air_acceleration / deceleration | 650 / 650 |
| run_reduce | 400 (air x0.65) |
| air_multiplier | 0.65 |
| jump_speed | -120 |
| jump_h_boost | 40 |
| var_jump_time | 0.2 |
| gravity | 900 |
| half_gravity_threshold | 40 |
| max_fall_speed / fast | 160 / 240 |
| fast_max_accel | 300 |
| jump_buffer_time / coyote_time | 0.08 / 0.1 |
| dash_speed / duration | 240 / 0.15 |
| dash_freeze / end_speed | 0.05 / 160 |
| dash cooldown / refill delay | 0.2 / 0.1 |
| dash_attack_time | 0.3 |
| super / hyper | 260 / 325, y -60 |
| wall jump / wallbounce | 130 / -120, 170 / -160 |
| climb up / down | 45 / 80 |
| stamina | 110; grab 10/s; climb 45.45/s; climb jump 27.5 |
| tired threshold | 20 |
| wall slide | 20 -> 160 over 1.2 s |
| wall / wallbounce probe | 3 / 5 px |
| wall jump force / grab lockout | 0.16 / 0.16 |
| climb-jump conversion | 0.2 s |
| corner correction | 4 px |
| lift caps | x +/-250, y -130..0 |

`jump_speed = -120` is deliberate: with 900 gravity, a 0.2 s variable-jump
window, and apex half gravity it produces roughly the current 32 px jump.
`-105` would produce about 27 px and invalidate existing room spacing. The value
stays a resource field so a future exact-scale project can use `-105`.

## Dash

On start:

- Spend one charge.
- Normalize the eight-way direction.
- Set `dash_remaining = duration`, `dash_attack_remaining = 0.3`,
  `freeze_remaining = 0.05`.
- Set `velocity = direction * dash_speed`.
- Request a global freeze.

During dash:

- No gravity or horizontal input.
- Velocity is the dash vector.
- A jump press checks wallbounce first, then super/hyper.
- Reaching the ground with a down-diagonal dash sets `ducking`.

On end:

- Set `velocity = direction * end_speed`.
- Return to NORMAL; dash-attack timer may still be running.

## Wall And Stamina

The wall probe is a short horizontal `test_move`/shape query at 3 px. A wall
contact requires a mostly horizontal normal.

`PlayerStamina` is a small node owned by the player. It drains through the wall
state, refills on landing, on water entry, on respawn/save restore, and exposes
`is_tired()` / `is_empty()`. Stamina is game-specific and stays out of
Platformer Kit.

## Global Freeze

`GameFreeze` is an autoload with `PROCESS_MODE_ALWAYS`:

- `freeze(seconds)` pauses the scene tree.
- It counts down in `_process` and only unpauses if it owned the pause.
- It captures jump/dash edges while frozen so an instant super/hyper input is
  not lost.
- HUD and audio stay on `PROCESS_MODE_ALWAYS`; gameplay animations stop with the
  tree.

## Platform Integration

- `PlayerController` sets `platform_on_leave = DO_NOTHING`.
- `EnvironmentProbe` samples `lift_velocity` from moving platform bodies only;
  a conveyor's `constant_linear_velocity` is excluded from lift.
- Jump and dash add lift, clamped to x +/-250 and y -130..0.
- Platforms and conveyors still carry the player through `move_and_slide`.
- Conveyors carry but do not launch a jump by default.
- Dash distance remains additive with platform carry, as in Celeste's moving
  solids; lift caps prevent runaway launches.

## 60/120 Hz

- All timers are seconds. No `1.0 / 60.0` gameplay constants.
- Input buffers and freeze durations are seconds.
- Wall/corner probes are pixels, not ticks.
- Gameplay and animation update in `_physics_process(delta)`.
- Tests run the same rule step with `1/60` and `1/120` and compare elapsed
  outcomes.

## Testing

Headless tests cover:

- Run acceleration, over-speed friction, air multiplier.
- Variable jump, apex half gravity, fast fall, jump buffer/coyote.
- Dash freeze, duration, end speed, cooldown, refill delay.
- Super/hyper/wavedash/wallbounce speeds and ducking.
- Wall grab, climb stamina, wall slide, climb jump refund, wall jump lockout.
- Platform carry, lift caps, conveyor no-launch.
- 60/120 equivalence for pure rule steps.
- Existing runtime suite regressions.

## File Plan

- `addons/platformer_kit/character/resources/movement_profile.gd`
- `addons/platformer_kit/character/motor/movement_context.gd`
- `addons/platformer_kit/character/motor/character_motor_2d.gd`
- `addons/platformer_kit/character/sensors/environment_probe.gd`
- `addons/platformer_kit/character/environment/character_environment_snapshot.gd`
- `addons/platformer_abilities/abilities/dash/dash_ability_definition.gd`
- `addons/platformer_abilities/abilities/dash/dash_ability_runtime.gd`
- `addons/platformer_abilities/abilities/dash/default_dash.tres`
- `scripts/globals/game_freeze.gd`
- `scripts/player/player_controller.gd`
- `scripts/player/player_stamina.gd`
- `scripts/player/player_motion_state.gd`
- `game/player/player_ability_loadout.gd`
- `resources/player/default_player_tuning.tres`
- `addons/platformer_kit/character/resources/default_movement_profile.tres`
- `scenes/player/player.tscn`
- `tests/player/...`, `tests/platformer_kit/...`, `tests/platformer_abilities/...`
- `tests/runtime_suite.gd`
- `docs/tuning.md`, `docs/controls.md`

## Stage Order

1. NORMAL rules and tuning fields.
2. DASH, freeze, dash attack, super/hyper/wavedash.
3. WALL_GRAB / WALL_SLIDE, stamina, wall jump, wallbounce.
4. Visual states, global freeze input buffering, 60/120 tests.
5. Room validation and tuning pass.
