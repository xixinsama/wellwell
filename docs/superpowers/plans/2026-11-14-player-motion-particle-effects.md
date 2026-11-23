# Player Motion Particle Effects Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development (recommended) or executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Add four small PixelFX effects for jumping, running, landing, and post-Killzone respawn without changing movement, health, or existing room data.

**Architecture:** A `PlayerMotionEffects` child owns short-lived, world-space `PixelFx2D` nodes. `PlayerController` reports actual motor events, while a reusable `Killzone` respawns first and explicitly requests the hurt effect second. Four deterministic game-owned effect scripts use PixelFX's BAKED rendering path.

**Tech Stack:** Godot 4.7.2, GDScript, PixelFX 0.3.0, existing Node-based runtime tests, headless Godot rendering.

---

## File map

- Vendor: `addons/pixelfx/` from `D:\Godot4\GodotProject\pixelfx-godot-main\godot\addons\pixelfx`.
- Create: `game/player/effects/{jump_dust,run_dust,land_dust,respawn_hurt}.gd` — drawing and particle motion only.
- Create: `game/player/player_motion_effects.gd` — effect nodes, cadence, facing, lifetime.
- Create: `scripts/world/killzone.gd`, `scenes/world/killzone.tscn` — respawn-then-hurt trigger.
- Modify: `scripts/player/player_controller.gd`, `scenes/player/player.tscn` — thin composition hooks.
- Modify: `project.godot` — append only the PixelFX plugin entry; preserve its current user edits.
- Test: `tests/player/test_player_motion_effects.gd`, `tests/world/test_killzone.gd`.
- Reuse: `tests/run_test_script.gd` — existing focused runner for one `run() -> Array[String]` test without unrelated suite failures.
- Modify: `tests/runtime_suite.gd` — register only the two feature test scripts.
- Create: `tests/player/render_player_motion_effects.gd` — development-only contact-sheet renderer.
- Create: `docs/player-effects.md`, `docs/previews/player-motion-effects.png`.

Godot executable for every command:

```powershell
$godot = 'D:\Godot4\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe'
```

Baseline recorded before implementation: the full suite exits 1 because `tests/world/test_save_point.gd` expects `SavePoint/VisualRoot` while `addons/platformer_kit/world/entities/save_point.tscn` names it `Visual`. That unrelated failure is not to be fixed or hidden by this feature.

### Task 1: Dependency and focused test runner

**Files:**
- Create: `addons/pixelfx/`
- Reuse: `tests/run_test_script.gd`
- Modify: `project.godot:38`

- [x] **Step 1: Preserve the existing edits and copy only the plugin**

```powershell
git status --short
$source = 'D:\Godot4\GodotProject\pixelfx-godot-main\godot\addons\pixelfx'
$target = 'D:\Godot4\GodotProject\wellwell\addons\pixelfx'
if (Test-Path -LiteralPath $target) { throw "Refusing to overwrite $target" }
Copy-Item -LiteralPath $source -Destination $target -Recurse
```

Expected: `addons/pixelfx/plugin.cfg` and `nodes/pixel_fx_2d.gd` exist; the external checkout remains unchanged.

- [x] **Step 2: Enable PixelFX with a targeted edit**

Replace only the existing `enabled` line in `[editor_plugins]` with this complete line, then leave every other byte of the file unchanged:

```ini
enabled=PackedStringArray("res://addons/input_mapping/plugin.cfg", "res://addons/metroidvania_kit/plugin.cfg", "res://addons/pixelfx/plugin.cfg", "res://addons/platformer_abilities/plugin.cfg", "res://addons/platformer_combat/plugin.cfg", "res://addons/platformer_debug/plugin.cfg", "res://addons/platformer_kit/plugin.cfg", "res://addons/world_editor/plugin.cfg")
```

Do not stage the file wholesale, because it already contains user edits.

Run:

```powershell
& $godot --headless --editor --path . --import --quit
```

Expected: exit 0 and no PixelFX script parse error.

- [x] **Step 3: Reuse the existing focused runner**

Use the existing `tests/run_test_script.gd`; it already accepts one test path, instantiates a Node exposing `run()`, prints each failure, and returns a nonzero exit code on failure. Do not add a second runner.

Run without a test argument:

```powershell
& $godot --headless --path . -s res://tests/run_test_script.gd
```

Expected: exit 2 with the usage message, proving argument validation works.

- [x] **Step 4: Commit only owned files**

```powershell
git add -- addons/pixelfx
git diff --cached --check
git commit -m "build: add pixelfx runtime"
```

Do not stage `project.godot`; its PixelFX enablement remains a deliberate working-tree edit alongside the user's existing settings.

### Task 2: Four deterministic PixelFX effects

**Files:**
- Create: `game/player/effects/jump_dust.gd`
- Create: `game/player/effects/run_dust.gd`
- Create: `game/player/effects/land_dust.gd`
- Create: `game/player/effects/respawn_hurt.gd`
- Test: `tests/player/test_player_motion_effects.gd`

- [x] **Step 1: Write failing frame and motion tests**

Create the test with this complete initial content:

```gdscript
extends Node

const PX_PATH := "res://addons/pixelfx/core/px.gd"
const EFFECT_PATHS := [
	"res://game/player/effects/jump_dust.gd",
	"res://game/player/effects/run_dust.gd",
	"res://game/player/effects/land_dust.gd",
	"res://game/player/effects/respawn_hurt.gd",
]


func run() -> Array[String]:
	var failures: Array[String] = []
	var Px := load(PX_PATH)
	if Px == null:
		return ["PixelFX core is missing"]
	for path: String in EFFECT_PATHS:
		var script := load(path) as Script
		if script == null:
			failures.append("missing effect: %s" % path)
			continue
		var instance: RefCounted = Px.createFx(script, {})
		var meta: Dictionary = script.get("meta")
		var frame: RefCounted = Px.createFrame(meta.size[0], meta.size[1])
		instance.update(0.08)
		instance.draw(frame)
		if _visible_pixels(frame) == 0:
			failures.append("effect has no visible key frame: %s" % path)
		instance.update(float(meta.duration) + 0.1)
		frame.clear()
		instance.draw(frame)
		if _visible_pixels(frame) != 0:
			failures.append("one-shot does not end empty: %s" % path)
	_assert_land_spread(Px, failures)
	_assert_hurt_falls(Px, failures)
	return failures


func _visible_pixels(frame: RefCounted) -> int:
	var count := 0
	for color: int in frame.color:
		if color != 0:
			count += 1
	return count


func _assert_land_spread(Px: RefCounted, failures: Array[String]) -> void:
	var script := load(EFFECT_PATHS[2]) as Script
	if script == null:
		return
	var instance: RefCounted = Px.createFx(script, {})
	var particles: RefCounted = instance.impl.get("particles")
	var left := false
	var right := false
	for particle: Dictionary in particles.list:
		left = left or float(particle.vx) < 0.0
		right = right or float(particle.vx) > 0.0
	if not left or not right:
		failures.append("landing dust must travel both left and right")


func _assert_hurt_falls(Px: RefCounted, failures: Array[String]) -> void:
	var script := load(EFFECT_PATHS[3]) as Script
	if script == null:
		return
	var instance: RefCounted = Px.createFx(script, {})
	var particles: RefCounted = instance.impl.get("particles")
	var initial_y: Array[float] = []
	for particle: Dictionary in particles.list:
		initial_y.append(particle.y)
	instance.update(0.08)
	for index: int in range(initial_y.size()):
		if float(particles.list[index].y) <= initial_y[index]:
			failures.append("respawn hurt particles must fall downward")
			return
```

Run:

```powershell
& $godot --headless --path . -s res://tests/run_test_script.gd -- res://tests/player/test_player_motion_effects.gd
```

Expected RED: four `missing effect:` failures, not a parser error.

- [x] **Step 2: Implement jump dust**

```gdscript
extends "res://addons/pixelfx/core/effect.gd"

const Px := preload("res://addons/pixelfx/core/px.gd")
const P := Px.P

static var meta := {
	"name": "Player jump dust", "size": [24, 20], "origin": [12, 16],
	"duration": 0.4, "loop": false, "fps": 30,
	"options": {"palette": ["#625b61", "#a39a96", "#d2c8bb"], "seed": 11},
}

var particles: Px.Particles


func create(o: Dictionary) -> void:
	var colors := Px.fit(o.palette, 3)
	var rng := Px.Rng.new(o.seed)
	particles = Px.Particles.new({"rng": rng})
	for side: int in [-1, 1]:
		for index: int in range(2):
			particles.spawn(P.DUST, side * (1.0 + index), -1.0, side * rng.range(10.0, 18.0), -rng.range(4.0, 9.0), rng.range(0.18, 0.30), colors[1], rng.range(0.7, 1.1))
	for index: int in range(3):
		particles.spawn(P.GRIT, rng.range(-2.0, 2.0), -1.0, rng.range(-5.0, 5.0), rng.range(8.0, 16.0), rng.range(0.18, 0.28), colors[0])


func update(dt: float) -> void:
	particles.update(dt)


func draw(p: Px.Painter) -> void:
	particles.draw(p)
```

- [x] **Step 3: Implement one running footstep**

Create `run_dust.gd` with this complete content:

```gdscript
extends "res://addons/pixelfx/core/effect.gd"

const Px := preload("res://addons/pixelfx/core/px.gd")
const P := Px.P

static var meta := {
	"name": "Player run dust", "size": [16, 14], "origin": [8, 11],
	"duration": 0.32, "loop": false, "fps": 30,
	"options": {"palette": ["#625b61", "#a39a96", "#d2c8bb"], "seed": 23},
}

var particles: Px.Particles


func create(o: Dictionary) -> void:
	var colors := Px.fit(o.palette, 3)
	var rng := Px.Rng.new(o.seed)
	particles = Px.Particles.new({"rng": rng})
	for index: int in range(2):
		particles.spawn(P.DUST, -2.0 - index, -1.0, -rng.range(9.0, 16.0), -rng.range(3.0, 8.0), rng.range(0.18, 0.27), colors[1], rng.range(0.65, 1.0))


func update(dt: float) -> void:
	particles.update(dt)


func draw(p: Px.Painter) -> void:
	particles.draw(p)
```

- [x] **Step 4: Implement bilateral landing dust**

Create `land_dust.gd` with this complete content:

```gdscript
extends "res://addons/pixelfx/core/effect.gd"

const Px := preload("res://addons/pixelfx/core/px.gd")
const P := Px.P

static var meta := {
	"name": "Player land dust", "size": [32, 20], "origin": [16, 16],
	"duration": 0.52, "loop": false, "fps": 30,
	"options": {"palette": ["#625b61", "#a39a96", "#d2c8bb"], "seed": 37},
}

var particles: Px.Particles


func create(o: Dictionary) -> void:
	var colors := Px.fit(o.palette, 3)
	var rng := Px.Rng.new(o.seed)
	particles = Px.Particles.new({"rng": rng})
	for side: int in [-1, 1]:
		for index: int in range(3):
			particles.spawn(P.DUST, side * rng.range(1.0, 3.0), -rng.range(0.5, 1.5), side * rng.range(12.0, 24.0), -rng.range(6.0, 14.0), rng.range(0.30, 0.44), colors[1], rng.range(0.8, 1.35), index * 0.015)


func update(dt: float) -> void:
	particles.update(dt)


func draw(p: Px.Painter) -> void:
	particles.draw(p)
```

- [x] **Step 5: Implement falling red respawn particles**

Create `respawn_hurt.gd` with this complete content:

```gdscript
extends "res://addons/pixelfx/core/effect.gd"

const Px := preload("res://addons/pixelfx/core/px.gd")
const P := Px.P

static var meta := {
	"name": "Player respawn hurt", "size": [24, 32], "origin": [12, 16],
	"duration": 0.58, "loop": false, "fps": 30,
	"options": {"palette": ["#6e1f35", "#c43c52", "#ff7770"], "seed": 51},
}

var particles: Px.Particles


func create(o: Dictionary) -> void:
	var colors := Px.fit(o.palette, 3)
	var rng := Px.Rng.new(o.seed)
	particles = Px.Particles.new({"rng": rng})
	for index: int in range(9):
		particles.spawn(P.FLAKE, rng.range(-3.0, 3.0), rng.range(-7.0, -2.0), rng.range(-4.0, 4.0), rng.range(12.0, 22.0), rng.range(0.30, 0.49), colors[index % colors.size()], 1.0, index * 0.006)


func update(dt: float) -> void:
	particles.update(dt)


func draw(p: Px.Painter) -> void:
	particles.draw(p)
```

- [x] **Step 6: Verify GREEN and commit**

Run the focused test from Step 1. Expected: exit 0 with no failures. Inspect any parser warning before continuing.

```powershell
git add -- game/player/effects tests/player/test_player_motion_effects.gd
git diff --cached --check
git commit -m "feat: draw player motion pixelfx effects"
```

### Task 3: Effect-node ownership and running cadence

**Files:**
- Create: `game/player/player_motion_effects.gd`
- Test: `tests/player/test_player_motion_effects.gd`

- [x] **Step 1: Append failing component behavior tests**

Append these methods and add these two calls immediately before `return failures` in `run()`:

```gdscript
	_assert_component_cadence_and_space(failures)
	_assert_component_direction_and_completion(failures)
```

The appended methods are:

```gdscript
func _assert_component_cadence_and_space(failures: Array[String]) -> void:
	var script := load("res://game/player/player_motion_effects.gd") as Script
	if script == null:
		failures.append("player motion effects component is missing")
		return
	var actor := Node2D.new()
	add_child(actor)
	actor.global_position = Vector2(12, 18)
	var effects := script.new() as Node2D
	actor.add_child(effects)
	effects.call("update_motion", 0.14, true, 100.0, 1)
	if effects.get_child_count() != 1:
		failures.append("running did not emit one footstep")
	var footstep := effects.get_child(0) as Node2D
	var emitted_at := footstep.global_position
	actor.global_position.x += 30.0
	if footstep.global_position != emitted_at:
		failures.append("footstep followed the actor instead of staying in world space")
	effects.call("update_motion", 0.01, true, 100.0, 1)
	if effects.get_child_count() != 1:
		failures.append("running ignored its emission interval")
	effects.call("play_land")
	var count_after_land := effects.get_child_count()
	effects.call("update_motion", 0.01, true, 100.0, 1)
	if effects.get_child_count() != count_after_land:
		failures.append("landing and running emitted overlapping dust")
	effects.call("update_motion", 0.2, false, 100.0, 1)
	effects.call("update_motion", 0.2, true, 0.0, 1)
	if effects.get_child_count() != count_after_land:
		failures.append("airborne or stationary movement emitted running dust")
	effects.call("clear_effects")
	for child: Node in effects.get_children():
		if not child.is_queued_for_deletion():
			failures.append("clear_effects did not release transient nodes")
	actor.free()


func _assert_component_direction_and_completion(failures: Array[String]) -> void:
	var script := load("res://game/player/player_motion_effects.gd") as Script
	if script == null:
		return
	var effects := script.new() as Node2D
	add_child(effects)
	effects.call("update_motion", 0.14, true, -100.0, -1)
	if effects.get_child_count() != 1 or not bool(effects.get_child(0).get("flip")):
		failures.append("left-running dust was not mirrored")
	effects.call("play_jump")
	effects.call("play_hurt")
	for child: Node in effects.get_children():
		if not bool(child.get("free_when_done")):
			failures.append("one-shot does not free itself")
		child.call("_process", 2.0)
		if not child.is_queued_for_deletion():
			failures.append("finished one-shot was not queued for release")
	effects.free()
```

Expected RED: `player motion effects component is missing`.

- [x] **Step 2: Implement the component**

```gdscript
class_name PlayerMotionEffects
extends Node2D

const PIXEL_FX := preload("res://addons/pixelfx/nodes/pixel_fx_2d.gd")
const JUMP_DUST := preload("res://game/player/effects/jump_dust.gd")
const RUN_DUST := preload("res://game/player/effects/run_dust.gd")
const LAND_DUST := preload("res://game/player/effects/land_dust.gd")
const RESPAWN_HURT := preload("res://game/player/effects/respawn_hurt.gd")

@export var run_min_speed := 8.0
@export var run_step_interval := 0.14

var _run_cooldown := 0.0


func play_jump() -> void:
	_spawn(JUMP_DUST)


func play_land() -> void:
	_run_cooldown = run_step_interval
	_spawn(LAND_DUST)


func play_hurt() -> void:
	_spawn(RESPAWN_HURT)


func update_motion(delta: float, grounded: bool, horizontal_speed: float, facing: int) -> void:
	if not grounded or absf(horizontal_speed) < run_min_speed:
		_run_cooldown = 0.0
		return
	_run_cooldown = maxf(_run_cooldown - maxf(delta, 0.0), 0.0)
	if _run_cooldown > 0.0:
		return
	_spawn(RUN_DUST, facing < 0, Vector2(-2.0 * float(facing), 0.0))
	_run_cooldown = run_step_interval


func clear_effects() -> void:
	_run_cooldown = 0.0
	for child: Node in get_children():
		if child is CanvasItem:
			child.hide()
		child.queue_free()


func _spawn(effect_script: Script, flipped: bool = false, offset: Vector2 = Vector2.ZERO) -> Node2D:
	var fx := PIXEL_FX.new() as Node2D
	fx.top_level = true
	fx.set("effect_script", effect_script)
	fx.set("autoplay", false)
	fx.set("free_when_done", true)
	fx.set("flip", flipped)
	fx.set("additive_light", false)
	add_child(fx)
	fx.global_position = global_position + offset
	fx.call("play")
	return fx
```

- [x] **Step 3: Verify GREEN and commit**

Run the focused player test; expected exit 0.

```powershell
git add -- game/player/player_motion_effects.gd tests/player/test_player_motion_effects.gd
git diff --cached --check
git commit -m "feat: manage player motion effect playback"
```

### Task 4: Player controller and scene integration

**Files:**
- Modify: `scripts/player/player_controller.gd`
- Modify: `scenes/player/player.tscn`
- Test: `tests/player/test_player_motion_effects.gd`

- [x] **Step 1: Add failing controller contract assertions**

Append a test that instantiates `scenes/player/player.tscn`, replaces `MotionEffects` before adding the player with the recorder below, and verifies the public respawn behavior:

```gdscript
class EffectsRecorder:
	extends Node
	var events: Array[String] = []

	func play_jump() -> void:
		events.append("jump")

	func play_land() -> void:
		events.append("land")

	func play_hurt() -> void:
		events.append("hurt:%s" % str((get_parent() as Node2D).global_position))

	func update_motion(_delta: float, _grounded: bool, _speed: float, _facing: int) -> void:
		pass

	func clear_effects() -> void:
		events.append("clear")


func _assert_player_composition(failures: Array[String]) -> void:
	var packed := load("res://scenes/player/player.tscn") as PackedScene
	if packed == null:
		failures.append("player scene is missing")
		return
	var player := packed.instantiate() as CharacterBody2D
	var old_effects := player.get_node_or_null("MotionEffects")
	if old_effects != null:
		player.remove_child(old_effects)
		old_effects.free()
	var recorder := EffectsRecorder.new()
	recorder.name = "MotionEffects"
	player.add_child(recorder)
	add_child(player)
	if not player.has_method("play_hurt_effect"):
		failures.append("player has no explicit post-respawn hurt-effect entry")
	else:
		player.respawn_at(Vector2(68, 140))
		if recorder.events != ["clear"]:
			failures.append("ordinary respawn must clear old effects without hurt: %s" % str(recorder.events))
		player.play_hurt_effect()
		if recorder.events.back() != "hurt:(68, 140)":
			failures.append("hurt effect did not use the post-respawn position")
	player.free()
```

Add `_assert_player_composition(failures)` before `return failures` in `run()`, then add this source-order assertion method as well:

```gdscript
func _assert_controller_event_order(failures: Array[String]) -> void:
	var source := FileAccess.get_file_as_string("res://scripts/player/player_controller.gd")
	var jump_hook := source.find("_movement_context.just_jumped")
	var slide := source.find("move_and_slide()")
	var land_hook := source.find("not was_on_floor and is_on_floor()")
	var run_hook := source.find("\"update_motion\"", slide)
	if jump_hook < 0:
		failures.append("jump effect is not driven by actual just_jumped")
	if slide < 0 or land_hook <= slide or run_hook <= slide:
		failures.append("landing and running hooks must follow move_and_slide")
```

Call `_assert_controller_event_order(failures)` before `return failures`. Expected RED: missing node, entry method, and actual-event hooks.

- [x] **Step 2: Add the scene component**

Add an external resource for `res://game/player/player_motion_effects.gd`, increment `load_steps` from 7 to 8, and add:

```ini
[node name="MotionEffects" type="Node2D" parent="."]
script = ExtResource("6_motion_effects")
```

- [x] **Step 3: Wire actual motor events**

In `player_controller.gd` add:

```gdscript
@onready var _motion_effects: Node = get_node_or_null("MotionEffects")
var _has_motion_sample := false
```

Immediately after `_motor.call("step", ...)` add:

```gdscript
if _movement_context.just_jumped and _motion_effects != null:
	_motion_effects.call("play_jump")
```

Immediately after `move_and_slide()` add:

```gdscript
var landed := _has_motion_sample and not was_on_floor and is_on_floor()
if landed and _motion_effects != null:
	_motion_effects.call("play_land")
```

After `_world_velocity = get_real_velocity()` add:

```gdscript
if _motion_effects != null:
	_motion_effects.call("update_motion", delta, is_on_floor(), _world_velocity.x, facing)
_has_motion_sample = true
```

At the start of `respawn_at()` add:

```gdscript
if _motion_effects != null:
	_motion_effects.call("clear_effects")
_has_motion_sample = false
```

Add the explicit public entry:

```gdscript
func play_hurt_effect() -> void:
	if _motion_effects != null:
		_motion_effects.call("play_hurt")
```

Do not change `_play_jump_intent_feedback()` or any movement values.

- [x] **Step 4: Verify GREEN and commit**

Run the focused player test and existing motor integration test separately. Expected: both exit 0.

```powershell
& $godot --headless --path . -s res://tests/run_test_script.gd -- res://tests/platformer_kit/character/test_character_motor_integration.gd
git add -- scripts/player/player_controller.gd scenes/player/player.tscn tests/player/test_player_motion_effects.gd
git diff --cached --check
git commit -m "feat: trigger effects from player movement"
```

### Task 5: Killzone respawn-then-hurt behavior

**Files:**
- Create: `scripts/world/killzone.gd`
- Create: `scenes/world/killzone.tscn`
- Test: `tests/world/test_killzone.gd`
- Modify: `tests/runtime_suite.gd`

- [x] **Step 1: Write the failing Killzone test**

```gdscript
extends Node

class FakePlayer:
	extends Node2D
	var spawn_position := Vector2(68, 140)
	var events: Array[String] = []

	func respawn_at(target: Vector2) -> void:
		global_position = target
		events.append("respawn")

	func play_hurt_effect() -> void:
		events.append("hurt:%s" % str(global_position))


func run() -> Array[String]:
	var failures: Array[String] = []
	var packed := load("res://scenes/world/killzone.tscn") as PackedScene
	if packed == null:
		return ["reusable Killzone scene is missing"]
	var zone := packed.instantiate() as Area2D
	add_child(zone)
	if zone.collision_layer != 0 or zone.collision_mask != 2:
		failures.append("Killzone must detect player collision layer 2")
	var player := FakePlayer.new()
	player.add_to_group("player")
	add_child(player)
	zone.body_entered.emit(player)
	if player.events != ["respawn", "hurt:(68, 140)"]:
		failures.append("Killzone must respawn before hurt feedback: %s" % str(player.events))
	var bystander := Node2D.new()
	add_child(bystander)
	zone.body_entered.emit(bystander)
	if player.events.size() != 2:
		failures.append("non-player contact retriggered Killzone")
	zone.free()
	player.free()
	bystander.free()
	return failures
```

Run with the focused runner. Expected RED: `reusable Killzone scene is missing`.

- [x] **Step 2: Implement the trigger and reusable scene**

`killzone.gd`:

```gdscript
class_name Killzone
extends Area2D


func _ready() -> void:
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node2D) -> void:
	if not body.is_in_group("player") or not body.has_method("respawn_at"):
		return
	var target: Variant = body.get("spawn_position")
	if not target is Vector2:
		return
	body.call("respawn_at", target)
	if body.has_method("play_hurt_effect"):
		body.call("play_hurt_effect")
```

`killzone.tscn`:

```ini
[gd_scene load_steps=3 format=3]

[ext_resource type="Script" path="res://scripts/world/killzone.gd" id="1_killzone"]

[sub_resource type="RectangleShape2D" id="RectangleShape2D_killzone"]
size = Vector2(32, 16)

[node name="Killzone" type="Area2D"]
collision_layer = 0
collision_mask = 2
script = ExtResource("1_killzone")

[node name="CollisionShape2D" type="CollisionShape2D" parent="."]
shape = SubResource("RectangleShape2D_killzone")
```

Run the focused test; expected GREEN.

- [x] **Step 3: Register exactly the two feature tests**

Add these entries to `TESTS` in `tests/runtime_suite.gd`:

```gdscript
	preload("res://tests/player/test_player_motion_effects.gd"),
	preload("res://tests/world/test_killzone.gd"),
```

Run both focused tests and the complete suite. Expected: both feature tests exit 0; the complete suite may still report only the recorded SavePoint baseline failure, with no new failure text.

- [x] **Step 4: Commit**

```powershell
git add -- scripts/world/killzone.gd scenes/world/killzone.tscn tests/world/test_killzone.gd tests/runtime_suite.gd
git diff --cached --check
git commit -m "feat: add respawn hurt killzone feedback"
```

### Task 6: Render, inspect, refine, and document

**Files:**
- Create: `tests/player/render_player_motion_effects.gd`
- Create: `docs/previews/player-motion-effects.png`
- Create: `docs/player-effects.md`
- Modify only if visual inspection requires it: `game/player/effects/*.gd`

- [x] **Step 1: Render all four effects to one enlarged contact sheet**

Create `tests/player/render_player_motion_effects.gd` with this complete content. Each cell includes the actual 8×8 green player block for scale, uses a 40×40 logical-pixel cell, and is enlarged 6× with nearest-neighbor sampling:

```gdscript
extends SceneTree

const Px := preload("res://addons/pixelfx/core/px.gd")
const EFFECT_PATHS := [
	"res://game/player/effects/jump_dust.gd",
	"res://game/player/effects/run_dust.gd",
	"res://game/player/effects/land_dust.gd",
	"res://game/player/effects/respawn_hurt.gd",
]
const TIMES := [0.0, 0.08, 0.16, 0.28, 0.44]
const CELL_SIZE := 40
const SCALE := 6


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var scaled_size := CELL_SIZE * SCALE
	var sheet := Image.create(TIMES.size() * scaled_size, EFFECT_PATHS.size() * scaled_size, false, Image.FORMAT_RGBA8)
	sheet.fill(Color("18202a"))
	for row: int in range(EFFECT_PATHS.size()):
		var script := load(EFFECT_PATHS[row]) as Script
		if script == null:
			push_error("preview effect missing: %s" % EFFECT_PATHS[row])
			quit(1)
			return
		var meta: Dictionary = script.get("meta")
		for column: int in range(TIMES.size()):
			var instance: RefCounted = Px.createFx(script, {})
			instance.update(TIMES[column])
			var frame: RefCounted = Px.createFrame(meta.size[0], meta.size[1])
			instance.draw(frame)
			var rgba: PackedByteArray = Px.composite(frame, PackedByteArray(), null)
			var image := Image.create_from_data(frame.w, frame.h, false, Image.FORMAT_RGBA8, rgba)
			var cell := Image.create(CELL_SIZE, CELL_SIZE, false, Image.FORMAT_RGBA8)
			cell.fill(Color(0, 0, 0, 0))
			var feet := Vector2i(CELL_SIZE / 2, 26)
			cell.fill_rect(Rect2i(feet.x - 4, feet.y - 8, 8, 8), Color("4bdb9f"))
			cell.blit_rect(image, Rect2i(0, 0, frame.w, frame.h), feet - Vector2i(meta.origin[0], meta.origin[1]))
			cell.resize(scaled_size, scaled_size, Image.INTERPOLATE_NEAREST)
			sheet.blit_rect(cell, Rect2i(0, 0, scaled_size, scaled_size), Vector2i(column * scaled_size, row * scaled_size))
	DirAccess.make_dir_recursive_absolute("res://docs/previews")
	var error := sheet.save_png("res://docs/previews/player-motion-effects.png")
	if error != OK:
		push_error("preview save failed: %s" % error_string(error))
		quit(1)
		return
	quit(0)
```

Rows are jump, run, land, hurt; columns are 0.00, 0.08, 0.16, 0.28 and 0.44 seconds. No font or runtime image asset is needed.

Run:

```powershell
& $godot --headless --path . -s res://tests/player/render_player_motion_effects.gd
```

Expected: exit 0 and a non-empty PNG.

- [x] **Step 2: Perform three visual refinement rounds**

Open the PNG with the image reader. Round 1 checks readable silhouettes at the 8-pixel character scale; round 2 checks bilateral landing motion, restrained running density, and downward red particles; round 3 checks empty end frames and canvas clipping. After each correction, rerun the focused frame test and renderer before opening the next image. Do not add glow, shake, or more particles merely to make the sheet busier.

- [x] **Step 3: Document use and visual parameters**

Write `docs/player-effects.md` with these explicit instructions:

```markdown
# 角色运动粒子效果

四套效果位于 `game/player/effects/`，由 `MotionEffects` 节点自动播放。使用 PixelFX BAKED 缓存，不需要贴图。

- 跳跃：真实 `just_jumped` 起跳时播放。
- 奔跑：着地且实际水平速度至少 8 px/s，每 0.14 秒一脚尘。
- 落地：未着地到着地的物理帧播放左右灰尘。
- 受伤：仅 Killzone 显式请求；普通传送不播放。

## 放置 Killzone

将 `scenes/world/killzone.tscn` 实例化到源房间的 `RoomContent/Entities`，调整 CollisionShape2D 覆盖陷阱或房间底部。它读取玩家的 `spawn_position`，先调用 `respawn_at()`，再在传送后的坐标播放红色下落粒子。不要直接修改 `scenes/rooms/generated/`；按项目既有烘焙流程更新运行时房间。

## 调整

颜色、粒子数量和时长在各效果的 `meta` 与 `create()` 中；奔跑阈值和间隔在 `PlayerMotionEffects` 的导出属性中。预览图行顺序为 jump、run、land、hurt，列时间为 0.00、0.08、0.16、0.28、0.44 秒。
```

- [x] **Step 4: Final verification**

Run both feature tests, the existing motor integration test, the full suite, and `git diff --check`. Confirm the full suite has no failure other than the pre-existing SavePoint mismatch, and inspect `git status` to ensure no generated room or user debug file was staged.

```powershell
git add -- game/player/effects tests/player/render_player_motion_effects.gd docs/player-effects.md docs/previews/player-motion-effects.png
git diff --cached --check
git commit -m "docs: add player effect preview and usage"
```

If Task 6 changed effect code, include those owned files in the final commit. Do not stage `project.godot`, user-modified maps, debug files, room templates, or generated rooms.

## Execution Result

- Implemented all four effects, controller composition, reusable Killzone, and a Killzone in `examples/movement_lab/movement_lab.tscn` for immediate F6 testing. No formal room or generated map was changed.
- Reused the existing `tests/run_test_script.gd`; the accidentally duplicated focused runner was removed before final delivery.
- Added real StaticBody2D/player tests for initial grounding, continuous grounding, airborne-to-ground landing, control lock, and post-respawn sampling. Added optional-interface Killzone tests.
- Code review found and verified fixes for jump debris clipping/fading and landing behavior coverage. The final re-review reported no remaining Critical or Important issues.
- Player effects, Killzone, movement-lab contract, and motor integration tests all exit 0. The movement lab and preview renderer also exit 0.
- The complete runtime suite still exits 1 only for the pre-existing `SavePoint/VisualRoot` versus `Visual` mismatch recorded in the baseline; no new failure text appears.
- The current model cannot directly consume image input. Three preview composition/pixel-outline review rounds were performed through generated PNG data and ASCII pixel inspection, and a fourth checked the corrected jump debris. The PNG remains available for human visual review; no claim of direct image viewing is made.
- `project.godot` retains the user's existing project-name edit and adds only the PixelFX plugin entry in the working tree. It is intentionally not staged wholesale.
