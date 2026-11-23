# Celeste-Rules Movement Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development (recommended) or executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement the approved Celeste rule set in `wellwell`: run/jump/fall curves, dash freeze/end speed/dash attack, no-grab wall grab/climb/stamina, super/hyper/wavedash/wallbounce, global freeze, 60/120-compatible timers, and platform lift caps.

**Architecture:** Keep `CharacterBody2D.move_and_slide()`. `CharacterMotor2D` owns NORMAL-state run/jump/fall physics. `PlayerController` becomes the state orchestrator for NORMAL, DASH, WALL_GRAB, WALL_SLIDE and delegates water/ladder to the existing components. Dash tuning stays in `platformer_abilities`; stamina and player state stay in `scripts/player/`.

**Tech Stack:** Godot 4.7 GDScript, headless runtime suite, existing `CharacterIntent`/`EnvironmentSnapshot` contracts.

---

## File Structure

- `addons/platformer_kit/character/resources/movement_profile.gd` — new rule fields and defaults.
- `addons/platformer_kit/character/resources/default_movement_profile.tres` — mirrored defaults.
- `addons/platformer_kit/character/motor/movement_context.gd` — jump/fall/dash/wall timer state.
- `addons/platformer_kit/character/motor/character_motor_2d.gd` — NORMAL run/jump/fall rules.
- `addons/platformer_kit/character/environment/character_environment_snapshot.gd` — lift fields.
- `addons/platformer_kit/character/sensors/environment_probe.gd` — lift sampling.
- `addons/platformer_kit/abilities/dash/dash_ability_definition.gd` — freeze/end/attack/refill fields.
- `addons/platformer_kit/abilities/dash/dash_ability_runtime.gd` — getters for the new fields.
- `addons/platformer_kit/abilities/dash/default_dash.tres` — tuned values.
- `game/player/player_ability_loadout.gd` — `try_start_dash()` / runtime access.
- `scripts/globals/game_freeze.gd` — global hit-stop autoload.
- `scripts/player/player_stamina.gd` — stamina node.
- `scripts/player/player_motion_state.gd` — state enum.
- `scripts/player/player_motion_rules.gd` — pure jump/lift/slide math.
- `scripts/player/player_controller.gd` — state orchestration.
- `scenes/player/player.tscn` — Stamina node.
- `project.godot` — GameFreeze autoload.
- `tests/player/test_celeste_movement_rules.gd` — rule tests.
- `tests/platformer_kit/character/test_character_motor_2d.gd` — updated motor tests.
- `tests/platformer_kit/character/test_movement_profile.gd` — updated defaults.
- `tests/platformer_kit/abilities/test_dash_ability.gd` — new dash fields.
- `tests/runtime_suite.gd` — register new test.
- `docs/tuning.md`, `docs/controls.md` — document behavior.

---

### Task 1: Extend MovementProfile and MovementContext

**Files:**
- Modify: `addons/platformer_kit/character/resources/movement_profile.gd`
- Modify: `addons/platformer_kit/character/resources/default_movement_profile.tres`
- Modify: `addons/platformer_kit/character/motor/movement_context.gd`
- Test: `tests/platformer_kit/character/test_movement_profile.gd`

- [ ] **Step 1: Write the failing profile test**

Replace `EXPECTED_VALUES` in `test_movement_profile.gd` with the new defaults:

```gdscript
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
    "climb_speed": 45.0,
    "wall_jump_speed": 130.0,
    "wall_jump_force_time": 0.16,
    "wall_grab_lockout": 0.16,
    "wall_check_distance": 3.0,
    "wallbounce_check_distance": 5.0,
    "wallbounce_speed": 170.0,
    "wallbounce_jump_speed": -160.0,
    "corner_correction": 4.0,
    "dash_attack_time": 0.3,
    "super_jump_speed": 260.0,
    "hyper_jump_speed": 325.0,
    "hyper_jump_vertical": -60.0,
    "lift_x_cap": 250.0,
    "lift_y_cap": -130.0,
}
```

- [ ] **Step 2: Run the test to confirm failure**

Run: `godot --headless --path . -s res://tests/run_runtime_suite.gd`
Expected: FAIL on new MovementProfile fields.

- [ ] **Step 3: Add fields and defaults**

Add to `MovementProfile`:

```gdscript
@export var run_reduce := 400.0
@export var air_multiplier := 0.65
@export var jump_h_boost := 40.0
@export var var_jump_time := 0.2
@export var half_gravity_threshold := 40.0
@export var fast_max_fall_speed := 240.0
@export var fast_max_accel := 300.0
@export var wall_jump_speed := 130.0
@export var wall_jump_force_time := 0.16
@export var wall_grab_lockout := 0.16
@export var wall_check_distance := 3.0
@export var wallbounce_check_distance := 5.0
@export var wallbounce_speed := 170.0
@export var wallbounce_jump_speed := -160.0
@export var wall_slide_start_speed := 20.0
@export var wall_slide_time := 1.2
@export var climb_down_speed := 80.0
@export var climb_jump_stamina := 27.5
@export var climb_jump_convert_time := 0.2
@export var corner_correction := 4.0
@export var dash_attack_time := 0.3
@export var super_jump_speed := 260.0
@export var hyper_jump_speed := 325.0
@export var hyper_jump_vertical := -60.0
@export var lift_x_cap := 250.0
@export var lift_y_cap := -130.0
@export var max_stamina := 110.0
@export var stamina_grab_drain := 10.0
@export var stamina_climb_drain := 45.4545
@export var stamina_tired_threshold := 20.0
```

Change existing defaults: `ground_acceleration=1000`, `ground_deceleration=1000`, `air_acceleration=650`, `air_deceleration=650`, `jump_speed=-120`, `gravity=900`, `max_fall_speed=160`, `jump_buffer_time=0.08`, `coyote_time=0.1`, `climb_speed=45`.

Add to `MovementContext`:

```gdscript
var max_fall_current := 160.0
var var_jump_remaining := 0.0
var var_jump_speed := 0.0
var climb_jump_window := 0.0
var dash_attack_remaining := 0.0
var wall_grab_lockout := 0.0
var force_move_x := 0.0
var force_move_x_remaining := 0.0
var ducking := false
```

Reset all of them in `reset()`.

- [ ] **Step 4: Update the default profile resource**

Mirror every changed field in `default_movement_profile.tres` explicitly.

- [ ] **Step 5: Run tests**

Run: `godot --headless --path . -s res://tests/run_runtime_suite.gd`
Expected: profile test passes; motor tests may still fail and are handled in Task 2.

- [ ] **Step 6: Commit**

```bash
git add addons/platformer_kit/character/resources/movement_profile.gd \
        addons/platformer_kit/character/resources/default_movement_profile.tres \
        addons/platformer_kit/character/motor/movement_context.gd \
        tests/platformer_kit/character/test_movement_profile.gd
git commit -m "feat: add Celeste movement tuning fields"
```

---

### Task 2: Rewrite NORMAL-State Run, Jump, and Fall

**Files:**
- Modify: `addons/platformer_kit/character/motor/character_motor_2d.gd`
- Modify: `tests/platformer_kit/character/test_character_motor_2d.gd`

- [ ] **Step 1: Replace motor tests**

Test grounded acceleration 1000, grounded decel 1000, air accel 650, over-cap friction (`vx=200`, air, run_reduce 400*0.65 = 260), gravity 900, terminal 160, variable jump clamp, and 60/120 equivalence.

- [ ] **Step 2: Run to confirm failure**

Run the runtime suite; expect old motor behavior failures.

- [ ] **Step 3: Implement horizontal rules**

```gdscript
func _apply_horizontal(context, intent, environment, profile, delta):
    var axis := clampf(intent.move_axis, -1.0, 1.0)
    var has_input := not is_zero_approx(axis)
    var target := axis * profile.max_speed
    var rate: float
    if has_input and absf(context.velocity.x) > profile.max_speed \
            and signf(context.velocity.x) == signf(axis):
        rate = profile.run_reduce * (1.0 if environment.grounded else profile.air_multiplier)
    elif environment.grounded:
        rate = profile.ground_acceleration if has_input else profile.ground_deceleration
    else:
        rate = profile.air_acceleration if has_input else profile.air_deceleration
    context.velocity.x = move_toward(context.velocity.x, target, rate * delta)
```

- [ ] **Step 4: Implement vertical rules**

Jump start:

```gdscript
context.velocity.y = profile.jump_speed
context.var_jump_remaining = profile.var_jump_time
context.var_jump_speed = context.velocity.y
context.velocity.x += profile.jump_h_boost * axis
context.velocity += _capped_lift(environment.lift_velocity, profile)
```

Vertical step:

```gdscript
if environment.grounded and context.velocity.y >= 0.0 and not context.just_jumped:
    context.velocity.y = 0.0
    context.max_fall_current = profile.max_fall_speed
    return

var target_max := profile.fast_max_fall_speed if intent.fast_fall else profile.max_fall_speed
context.max_fall_current = move_toward(
    context.max_fall_current, target_max, profile.fast_max_accel * delta
)
var gravity_scale := 1.0
if absf(context.velocity.y) < profile.half_gravity_threshold and intent.jump_held:
    gravity_scale = 0.5
context.velocity.y = move_toward(
    context.velocity.y, context.max_fall_current, profile.gravity * gravity_scale * delta
)
if context.var_jump_remaining > 0.0:
    if intent.jump_held:
        context.velocity.y = minf(context.velocity.y, context.var_jump_speed)
        context.var_jump_remaining = maxf(context.var_jump_remaining - delta, 0.0)
    else:
        context.var_jump_remaining = 0.0
```

Add `_capped_lift()`:

```gdscript
func _capped_lift(value: Vector2, profile: MovementProfile) -> Vector2:
    return Vector2(
        clampf(value.x, -profile.lift_x_cap, profile.lift_x_cap),
        clampf(value.y, profile.lift_y_cap, 0.0)
    )
```

- [ ] **Step 5: Run tests**

Run the runtime suite. Expected: motor tests pass; integration tests may need updating.

- [ ] **Step 6: Commit**

```bash
git add addons/platformer_kit/character/motor/character_motor_2d.gd \
        tests/platformer_kit/character/test_character_motor_2d.gd
git commit -m "feat: apply Celeste run and jump rules to normal motion"
```

---

### Task 3: Sample Platform Lift and Update Environment Snapshot

**Files:**
- Modify: `addons/platformer_kit/character/environment/character_environment_snapshot.gd`
- Modify: `addons/platformer_kit/character/sensors/environment_probe.gd`
- Test: `tests/platformer_kit/character/test_character_sensors.gd`

- [ ] **Step 1: Add lift fields**

In `CharacterEnvironmentSnapshot`:

```gdscript
var lift_velocity := Vector2.ZERO
var on_lift_platform := false
```

- [ ] **Step 2: Sample lift from the floor body**

In `EnvironmentProbe`, find the floor collider once and return its `get_motion_velocity()` when present; otherwise subtract `constant_linear_velocity` from `get_platform_velocity()` so a conveyor contributes zero lift.

- [ ] **Step 3: Test**

Extend `test_character_sensors.gd` to assert `lift_velocity` and `on_lift_platform` survive `CharacterSensors.capture()`.

- [ ] **Step 4: Run and commit**

Run the suite, then commit:

```bash
git add addons/platformer_kit/character/environment/character_environment_snapshot.gd \
        addons/platformer_kit/character/sensors/environment_probe.gd \
        tests/platformer_kit/character/test_character_sensors.gd
git commit -m "feat: expose moving-platform lift separately from conveyor velocity"
```

---

### Task 4: Extend Dash Definition, Runtime, and Loadout

**Files:**
- Modify: `addons/platformer_kit/abilities/dash/dash_ability_definition.gd`
- Modify: `addons/platformer_kit/abilities/dash/dash_ability_runtime.gd`
- Modify: `addons/platformer_kit/abilities/dash/default_dash.tres`
- Modify: `game/player/player_ability_loadout.gd`
- Test: `tests/platformer_kit/abilities/test_dash_ability.gd`
- Test: `tests/game/test_player_ability_loadout.gd`

- [ ] **Step 1: Add dash fields**

```gdscript
@export var freeze_seconds := 0.05
@export var end_speed := 160.0
@export var dash_attack_seconds := 0.3
@export var refill_cooldown_seconds := 0.1
```

Set `dash_duration = 0.15` and `cooldown_seconds = 0.2` in `default_dash.tres`.

- [ ] **Step 2: Add runtime getters**

```gdscript
func get_freeze_seconds() -> float: ...
func get_end_speed() -> float: ...
func get_dash_attack_seconds() -> float: ...
func get_refill_cooldown_seconds() -> float: ...
```

- [ ] **Step 3: Add loadout methods**

```gdscript
func try_start_dash(intent, environment, facing) -> bool
func get_dash_runtime() -> RefCounted
func get_dash_definition() -> Resource
```

Keep `get_motion_override()` for compatibility, implemented through `try_start_dash()`.

- [ ] **Step 4: Test and commit**

Add assertions for the four new fields and `try_start_dash()`. Commit:

```bash
git add addons/platformer_kit/abilities/dash \
        game/player/player_ability_loadout.gd \
        tests/platformer_kit/abilities/test_dash_ability.gd \
        tests/game/test_player_ability_loadout.gd
git commit -m "feat: add dash freeze, end speed, attack window and refill delay"
```

---

### Task 5: Add GameFreeze, Stamina, State Enum, and Player Scene Wiring

**Files:**
- Create: `scripts/globals/game_freeze.gd`
- Create: `scripts/player/player_stamina.gd`
- Create: `scripts/player/player_motion_state.gd`
- Create: `scripts/player/player_motion_rules.gd`
- Modify: `project.godot`
- Modify: `scenes/player/player.tscn`

- [ ] **Step 1: Implement GameFreeze**

Pause the tree for a duration, count down in `_process` with `PROCESS_MODE_ALWAYS`, only unpause a pause it owns, and buffer jump/dash edges while frozen.

- [ ] **Step 2: Implement PlayerStamina**

Node with `configure(profile)`, `drain(rate, delta)`, `spend(amount)`, `refund(amount)`, `refill()`, `is_tired()`, `is_empty()`, `get_current()`, and a `changed` signal.

- [ ] **Step 3: Implement PlayerMotionState and PlayerMotionRules**

State enum: `NORMAL`, `DASH`, `WALL_GRAB`, `WALL_SLIDE`, `SWIM`, `LADDER`, `HURT`.

Rules: super/hyper/wall jump/wallbounce velocities, wall-slide cap, direction from intent.

- [ ] **Step 4: Wire scene and autoload**

Add `GameFreeze` to `project.godot` and a `Stamina` Node to `player.tscn`.

- [ ] **Step 5: Commit**

```bash
git add scripts/globals/game_freeze.gd scripts/player/player_stamina.gd \
        scripts/player/player_motion_state.gd scripts/player/player_motion_rules.gd \
        project.godot scenes/player/player.tscn
git commit -m "feat: add global freeze, stamina and player motion scaffolding"
```

---

### Task 6: Orchestrate NORMAL and DASH in PlayerController

**Files:**
- Modify: `scripts/player/player_controller.gd`
- Test: `tests/player/test_celeste_movement_rules.gd`

- [ ] **Step 1: Add state fields and freeze input consumption**

Add `_state`, dash timers, direction, end speed, refill delay, jump buffer, ducking, and `GameFreeze` consumption.

- [ ] **Step 2: Add dash start and step**

On dash press: `try_start_dash()`, set timers, request global freeze, set velocity. On unpause: move at `dash_speed`, check jump branches, end at `end_speed`.

- [ ] **Step 3: Add super/hyper/wavedash/wallbounce**

Wallbounce first, then grounded/landing super/hyper. Set `var_jump_remaining`/`var_jump_speed` and clear jump timers.

- [ ] **Step 4: Add tests and run**

Test dash freeze field, end speed, dash-attack window, super/hyper speeds, and 60/120 timing.

- [ ] **Step 5: Commit**

```bash
git add scripts/player/player_controller.gd tests/player/test_celeste_movement_rules.gd
git commit -m "feat: add Celeste dash state, freeze and advanced jumps"
```

---

### Task 7: Add WALL_GRAB, WALL_SLIDE, Stamina, and Wall Jumps

**Files:**
- Modify: `scripts/player/player_controller.gd`
- Modify: `game/player/hero_animation_controller.gd`
- Test: `tests/player/test_celeste_movement_rules.gd`

- [ ] **Step 1: Add wall probe**

Use `test_move()` with a 3 px horizontal motion and a horizontal normal check. Add a 5 px variant for wallbounce.

- [ ] **Step 2: Add auto-grab and climb**

Hold toward wall enters `WALL_GRAB`. Up/down set climb velocity; grab/climb drain stamina; zero stamina enters `WALL_SLIDE`.

- [ ] **Step 3: Add wall jump and climb jump conversion**

Toward + jump = climb jump, deduct 27.5, open a 0.2 s conversion window. Away/neutral + jump = wall jump, 130 away, 0.16 s force and lockout. Away within the window converts and refunds.

- [ ] **Step 4: Add wall slide and wallbounce**

Wall slide cap lerps 20 -> 160 over 1.2 s. Up-dash + wall + jump within dash attack applies 170 / -160.

- [ ] **Step 5: Test and commit**

Add headless tests for stamina, grab lockout, conversion refund, wall slide cap, and wallbounce. Commit:

```bash
git add scripts/player/player_controller.gd game/player/hero_animation_controller.gd \
        tests/player/test_celeste_movement_rules.gd
git commit -m "feat: add no-grab wall grab, climb, stamina and wall jumps"
```

---

### Task 8: Update Docs and Run Full Verification

**Files:**
- Modify: `docs/tuning.md`
- Modify: `docs/controls.md`
- Modify: `README.md` if it lists movement.
- Test: `tests/runtime_suite.gd`

- [ ] **Step 1: Document the new controls and tuning**

Describe no-grab wall mapping, dash/super/hyper/wavedash, stamina, global freeze, and platform lift caps.

- [ ] **Step 2: Check every touched script**

```bash
godot --headless --path . --check-only -s res://scripts/player/player_controller.gd
godot --headless --path . --check-only -s res://scripts/player/player_stamina.gd
godot --headless --path . --check-only -s res://scripts/player/player_motion_rules.gd
godot --headless --path . --check-only -s res://scripts/globals/game_freeze.gd
```

- [ ] **Step 3: Run the full headless suite**

```bash
godot --headless --path . -s res://tests/run_runtime_suite.gd
```

Expected: exit code 0 and no `WARNING:` or `ERROR:` lines.

- [ ] **Step 4: Commit docs and final fixes**

```bash
git add docs/tuning.md docs/controls.md tests/runtime_suite.gd
git commit -m "docs: document Celeste movement rules and controls"
```
