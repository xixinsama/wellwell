# Ladder Climbing and Hero Animation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development (recommended) or executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Turn tile `(0,7)` and all its alternatives into ladder areas, add free climbing/repeated jumping/S+Jump fast dropping, and drive the supplied 10×10 Hero sprite sheet with a testable animation controller.

**Architecture:** A player-local `LadderMotionComponent2D` detects only `ladder_zone` areas and handles motion before the ordinary motor. A runtime builder under `Terrain` converts matching TileMap cells into zones in both authoring previews and baked terrain. A separate `HeroAnimationController` consumes movement and climb state, while `PlayerController` only routes input, motion, signals, and resets.

**Tech Stack:** Godot 4.7.2, GDScript, CharacterBody2D/Area2D/TileMapLayer, AnimatedSprite2D/SpriteFrames, existing RoomBaker and Node runtime tests.

---

## File map and safety

- Create reusable ladder code under `addons/platformer_kit/character/ladder/` and `addons/platformer_kit/world/entities/`.
- Create game tile conversion at `scripts/world/ladder_tile_area_builder.gd`.
- Create Hero driver at `game/player/hero_animation_controller.gd`, asset at `assets/generated/hero.png`, frames at `resources/player/hero_sprite_frames.tres`.
- Create asset generator `scripts/tools/build_hero_sprite_frames.gd` and targeted rebake runner `scripts/tools/rebake_room.gd`.
- Modify input/profile scripts, `scripts/player/player_controller.gd`, `scenes/player/player.tscn`, `scenes/rooms/template/level_template.tscn`.
- Create tests `tests/platformer_kit/character/test_ladder_motion.gd`, `tests/world/test_ladder_tiles.gd`, `tests/player/test_hero_animation.gd`; register them in `tests/runtime_suite.gd`.
- Modify existing `tests/platformer_kit/character/test_input_source.gd` and `test_movement_profile.gd`.
- Create `docs/ladders.md` and `docs/superpowers/plans/2026-11-15-ladder-climbing.md`.

Godot command used throughout:

```powershell
$godot = 'D:\Godot4\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe'
```

Run one test with the existing runner:

```powershell
& $godot --headless --path . -s res://tests/run_test_script.gd -- <res://test-path.gd>
```

Current full-suite baseline is exit 1 only for `SavePoint/VisualRoot` versus `Visual`; do not fix it in this feature. Preserve the user's modified TileSet/PNG, `room_01_00.tscn`, map resources, template debug additions, and debug overlay. Do not stage those user files wholesale. The template and rebaked room outputs may remain deliberate working-tree changes when they contain user work.

### Task 1: Vertical intent and climb tuning

**Files:**
- Modify: `addons/platformer_kit/character/input/character_intent.gd`
- Modify: `addons/platformer_kit/character/input/player_input_source.gd`
- Modify: `addons/platformer_kit/character/resources/movement_profile.gd`
- Test: `tests/platformer_kit/character/test_input_source.gd`
- Test: `tests/platformer_kit/character/test_movement_profile.gd`

- [x] **Step 1: Add failing input/profile assertions**

Add `"climb_speed": 72.0` to `EXPECTED_VALUES` in `test_movement_profile.gd`.

In `test_input_source.gd`, press and release `move_up` in addition to the existing inputs, then append:

```gdscript
	Input.action_press("move_up")
	var up_intent: RefCounted = source.call("get_intent")
	Input.action_release("move_up")
	if up_intent == null or not is_equal_approx(float(up_intent.get("vertical_axis")), -1.0):
		failures.append("PlayerInputSource did not translate move_up to negative vertical_axis")
	Input.action_press("move_down")
	var down_intent: RefCounted = source.call("get_intent")
	Input.action_release("move_down")
	if down_intent == null or not is_equal_approx(float(down_intent.get("vertical_axis")), 1.0):
		failures.append("PlayerInputSource did not translate move_down to positive vertical_axis")
	if not "vertical_axis" in neutral:
		failures.append("CharacterIntent is missing vertical_axis")
	elif not is_zero_approx(float(neutral.get("vertical_axis"))):
		failures.append("neutral CharacterIntent must have zero vertical_axis")
```

Run both focused tests. Expected RED: `vertical_axis` and `climb_speed` are missing.

- [x] **Step 2: Implement the minimal input/profile additions**

Add to `character_intent.gd`:

```gdscript
var vertical_axis := 0.0
```

Add to `player_input_source.gd`:

```gdscript
var move_up_action: StringName = &"move_up"
var move_down_action: StringName = &"move_down"
```

In `get_intent()`, immediately after `move_axis` add:

```gdscript
	intent.vertical_axis = Input.get_axis(move_up_action, move_down_action)
```

Add to `movement_profile.gd`:

```gdscript
@export var climb_speed := 72.0
```

- [x] **Step 3: Verify GREEN and commit**

Run `test_input_source.gd` and `test_movement_profile.gd`; both must exit 0.

```powershell
git add -- addons/platformer_kit/character/input/character_intent.gd addons/platformer_kit/character/input/player_input_source.gd addons/platformer_kit/character/resources/movement_profile.gd tests/platformer_kit/character/test_input_source.gd tests/platformer_kit/character/test_movement_profile.gd
git diff --cached --check
git commit -m "feat: add vertical intent and climb tuning"
```

### Task 2: Ladder zone and motion component

**Files:**
- Create: `addons/platformer_kit/world/entities/ladder_zone.gd`
- Create: `addons/platformer_kit/world/entities/ladder_zone.tscn`
- Create: `addons/platformer_kit/character/ladder/ladder_motion_component_2d.gd`
- Test: `tests/platformer_kit/character/test_ladder_motion.gd`

- [x] **Step 1: Write the failing motion tests**

Create `test_ladder_motion.gd` with helpers and assertions covering this exact public API:

```gdscript
extends Node

const COMPONENT_PATH := "res://addons/platformer_kit/character/ladder/ladder_motion_component_2d.gd"
const CONTEXT := preload("res://addons/platformer_kit/character/motor/movement_context.gd")
const INTENT := preload("res://addons/platformer_kit/character/input/character_intent.gd")
const PROFILE := preload("res://addons/platformer_kit/character/resources/movement_profile.gd")
const ZONE_SCENE_PATH := "res://addons/platformer_kit/world/entities/ladder_zone.tscn"


func run() -> Array[String]:
	var failures: Array[String] = []
	var script := load(COMPONENT_PATH) as Script
	if script == null:
		return ["ladder motion component is missing"]
	var component := script.new() as Node2D
	var body := CharacterBody2D.new()
	var body_shape := CollisionShape2D.new()
	body_shape.position = Vector2(0, -3)
	var rectangle := RectangleShape2D.new()
	rectangle.size = Vector2(6, 6)
	body_shape.shape = rectangle
	body.add_child(body_shape)
	add_child(body)
	body.add_child(component)
	var events: Array = []
	component.connect("climb_animation_requested", func(active: bool, direction: Vector2) -> void: events.append([active, direction]))
	var context: RefCounted = CONTEXT.new()
	var intent: RefCounted = INTENT.new()
	var profile: RefCounted = PROFILE.new()
	context.velocity = Vector2(15, 100)
	if not bool(component.call("apply_motion", context, intent, profile, 0.1, true, false)) or context.velocity != Vector2.ZERO:
		failures.append("neutral ladder contact must hover")
	intent.move_axis = 1.0
	component.call("apply_motion", context, intent, profile, 0.1, true, false)
	if context.velocity != Vector2(72, 0):
		failures.append("horizontal climb speed is wrong")
	intent.move_axis = 0.0
	intent.vertical_axis = -1.0
	component.call("apply_motion", context, intent, profile, 0.1, true, false)
	if context.velocity != Vector2(0, -72) or events.back() != [true, Vector2(0, -1)]:
		failures.append("W must climb upward and emit climb animation")
	intent.vertical_axis = 1.0
	component.call("apply_motion", context, intent, profile, 0.1, true, false)
	if context.velocity != Vector2(0, 72) or events.back() != [true, Vector2(0, 1)]:
		failures.append("S alone must climb downward, not drop")
	intent.vertical_axis = -1.0
	intent.move_axis = 1.0
	component.call("apply_motion", context, intent, profile, 0.1, true, false)
	if not is_equal_approx(context.velocity.length(), 72.0):
		failures.append("diagonal climbing must be normalized")
	intent.move_axis = 0.0
	intent.vertical_axis = 0.0
	intent.jump_pressed = true
	intent.jump_held = true
	component.call("apply_motion", context, intent, profile, 0.1, true, false)
	if context.velocity.y != -220.0 or not bool(context.just_jumped):
		failures.append("ladder jump did not use profile jump_speed")
	intent.jump_pressed = false
	context.velocity.y = -100.0
	component.call("apply_motion", context, intent, profile, 0.1, true, false)
	if context.velocity.y >= -100.0:
		failures.append("held ladder jump must continue upward")
	intent.jump_pressed = true
	component.call("apply_motion", context, intent, profile, 0.1, true, false)
	if context.velocity.y != -220.0:
		failures.append("repeated ladder jump was rejected")
	intent.jump_pressed = false
	intent.vertical_axis = 1.0
	intent.jump_pressed = true
	component.call("apply_motion", context, intent, profile, 0.1, true, false)
	if context.velocity.y != 0.0 or not bool(intent.fast_fall) or bool(component.call("apply_motion", context, intent, profile, 0.1, true, false)):
		failures.append("S+Jump must hand control to fast-fall Motor")
	intent.vertical_axis = 0.0
	intent.fast_fall = false
	component.call("apply_motion", context, intent, profile, 0.1, true, false)
	if not bool(intent.fast_fall):
		failures.append("drop latch must persist after button release")
	component.call("apply_motion", context, intent, profile, 0.1, true, true)
	intent.vertical_axis = -1.0
	component.call("apply_motion", context, intent, profile, 0.1, true, false)
	if context.velocity != Vector2(0, -72):
		failures.append("W must clear drop latch and resume climbing")
	intent.vertical_axis = 0.0
	if bool(component.call("apply_motion", context, intent, profile, 0.1, false, false)):
		failures.append("leaving the ladder must return control to ordinary Motor")
	_assert_zone_and_detector(component, failures)
	body.free()
	return failures


func _assert_zone_and_detector(component: Node2D, failures: Array[String]) -> void:
	var packed := load(ZONE_SCENE_PATH) as PackedScene
	if packed == null:
		failures.append("reusable ladder zone scene is missing")
		return
	var zone := packed.instantiate() as Area2D
	add_child(zone)
	var detector := component.get_node_or_null("Detector") as Area2D
	if detector == null:
		failures.append("ladder detector was not composed from player shape")
		zone.free()
		return
	detector.area_entered.emit(zone)
	if not bool(component.call("is_on_ladder")):
		failures.append("valid ladder zone was not detected")
	var ordinary := Area2D.new()
	add_child(ordinary)
	detector.area_entered.emit(ordinary)
	if ordinary.is_in_group("ladder_zone"):
		failures.append("ordinary Area2D was mislabeled as a ladder")
	detector.area_exited.emit(zone)
	if bool(component.call("is_on_ladder")):
		failures.append("leaving the ladder zone was not tracked")
	zone.free()
	ordinary.free()
```

Expected RED: component and zone are missing. The tests are intentionally independent of frame timing; real Area signals are emitted directly through the composed detector.

- [x] **Step 2: Implement the marker zone**

`ladder_zone.gd`:

```gdscript
class_name LadderZone
extends Area2D


func _ready() -> void:
	add_to_group("ladder_zone")
```

`ladder_zone.tscn`:

```ini
[gd_scene load_steps=3 format=3]

[ext_resource type="Script" path="res://addons/platformer_kit/world/entities/ladder_zone.gd" id="1_zone"]

[sub_resource type="RectangleShape2D" id="RectangleShape2D_zone"]
size = Vector2(8, 8)

[node name="LadderZone" type="Area2D"]
collision_layer = 4
collision_mask = 0
monitoring = false
script = ExtResource("1_zone")

[node name="CollisionShape2D" type="CollisionShape2D" parent="."]
shape = SubResource("RectangleShape2D_zone")
```

- [x] **Step 3: Implement the motion component**

```gdscript
class_name LadderMotionComponent2D
extends Node2D

signal climb_animation_requested(active: bool, direction: Vector2)

@export var body_shape_path := NodePath("../CollisionShape2D")

var _detector: Area2D
var _overlaps: Dictionary = {}
var _drop_latched := false
var _jump_active := false
var _last_active := false
var _last_direction := Vector2.ZERO


func _ready() -> void:
	var body_shape := get_node_or_null(body_shape_path) as CollisionShape2D
	if body_shape == null or body_shape.shape == null:
		push_warning("LadderMotion requires a valid player CollisionShape2D")
		return
	_detector = Area2D.new()
	_detector.name = "Detector"
	_detector.collision_layer = 0
	_detector.collision_mask = 4
	_detector.position = body_shape.position
	var detector_shape := CollisionShape2D.new()
	detector_shape.shape = body_shape.shape.duplicate()
	_detector.add_child(detector_shape)
	add_child(_detector)
	_detector.area_entered.connect(_on_area_entered)
	_detector.area_exited.connect(_on_area_exited)


func is_on_ladder() -> bool:
	for area: Object in _overlaps.keys():
		if not is_instance_valid(area):
			_overlaps.erase(area)
	return not _overlaps.is_empty()


func step(context: RefCounted, intent: RefCounted, environment: RefCounted, profile: RefCounted, delta: float) -> bool:
	return apply_motion(context, intent, profile, delta, is_on_ladder(), bool(environment.get("grounded")))


func apply_motion(context: RefCounted, intent: RefCounted, profile: RefCounted, delta: float, on_ladder: bool, grounded: bool) -> bool:
	if context == null or intent == null or profile == null:
		return false
	if not on_ladder:
		_drop_latched = false
		_jump_active = false
		_emit_animation(false, Vector2.ZERO)
		return false
	if grounded:
		_drop_latched = false
	if _drop_latched and float(intent.get("vertical_axis")) < 0.0:
		_drop_latched = false
	if _drop_latched:
		_prepare_drop(context, intent)
		return false
	if float(intent.get("vertical_axis")) > 0.0 and bool(intent.get("jump_pressed")):
		_drop_latched = true
		_prepare_drop(context, intent)
		return false
	if bool(intent.get("jump_pressed")):
		_jump_active = true
		context.set("velocity", Vector2(float(context.get("velocity").x), float(profile.get("jump_speed"))))
		context.set("just_jumped", true)
		_clear_jump_timers(context)
		_emit_animation(false, Vector2.ZERO)
		return true
	if _jump_active and bool(intent.get("jump_held")) and float(context.get("velocity").y) < 0.0:
		context.set("velocity", Vector2(float(context.get("velocity").x), float(context.get("velocity").y) + float(profile.get("gravity")) * maxf(delta, 0.0)))
		context.set("just_jumped", false)
		_clear_jump_timers(context)
		_emit_animation(false, Vector2.ZERO)
		return true
	_jump_active = false
	var direction := Vector2(clampf(float(intent.get("move_axis")), -1.0, 1.0), clampf(float(intent.get("vertical_axis")), -1.0, 1.0))
	if direction.length_squared() > 1.0:
		direction = direction.normalized()
	context.set("velocity", direction * float(profile.get("climb_speed")))
	context.set("just_jumped", false)
	_clear_jump_timers(context)
	_emit_animation(true, direction)
	return true


func reset() -> void:
	_drop_latched = false
	_jump_active = false
	_emit_animation(false, Vector2.ZERO)


func _prepare_drop(context: RefCounted, intent: RefCounted) -> void:
	_jump_active = false
	context.set("velocity", Vector2(float(context.get("velocity").x), maxf(float(context.get("velocity").y), 0.0)))
	context.set("just_jumped", false)
	_clear_jump_timers(context)
	intent.set("jump_pressed", false)
	intent.set("fast_fall", true)
	_emit_animation(false, Vector2.ZERO)


func _clear_jump_timers(context: RefCounted) -> void:
	context.set("jump_buffer_remaining", 0.0)
	context.set("coyote_remaining", 0.0)


func _emit_animation(active: bool, direction: Vector2) -> void:
	if active == _last_active and direction == _last_direction:
		return
	_last_active = active
	_last_direction = direction
	climb_animation_requested.emit(active, direction)


func _on_area_entered(area: Area2D) -> void:
	if area.is_in_group("ladder_zone"):
		_overlaps[area] = true


func _on_area_exited(area: Area2D) -> void:
	_overlaps.erase(area)
```

- [x] **Step 4: Verify GREEN and commit**

Run `test_ladder_motion.gd`; it must exit 0 with no parser/runtime error.

```powershell
git add -- addons/platformer_kit/world/entities/ladder_zone.gd addons/platformer_kit/world/entities/ladder_zone.tscn addons/platformer_kit/character/ladder/ladder_motion_component_2d.gd tests/platformer_kit/character/test_ladder_motion.gd
git diff --cached --check
git commit -m "feat: add free ladder motion and fast drop"
```

### Task 3: Tile-to-area builder and template

**Files:**
- Create: `scripts/world/ladder_tile_area_builder.gd`
- Modify: `scenes/rooms/template/level_template.tscn`
- Test: `tests/world/test_ladder_tiles.gd`

- [x] **Step 1: Write failing alternative-tile and bake tests**

Create `test_ladder_tiles.gd`:

```gdscript
extends Node

const BUILDER_PATH := "res://scripts/world/ladder_tile_area_builder.gd"
const TILESET_PATH := "res://resources/tilesets/primordial_tileset.tres"
const ROOM_BAKER := preload("res://addons/world_editor/authoring/room/room_baker.gd")


func run() -> Array[String]:
	var failures: Array[String] = []
	var script := load(BUILDER_PATH) as Script
	if script == null:
		return ["ladder tile area builder is missing"]
	var terrain := Node2D.new()
	add_child(terrain)
	var tiles := load(TILESET_PATH) as TileSet
	var layer := TileMapLayer.new()
	layer.tile_set = tiles
	terrain.add_child(layer)
	layer.set_cell(Vector2i(0, 0), 0, Vector2i(0, 7), 0)
	layer.set_cell(Vector2i(1, 0), 0, Vector2i(0, 7), 1)
	layer.set_cell(Vector2i(2, 0), 0, Vector2i(0, 6), 0)
	var builder := script.new() as Node2D
	terrain.add_child(builder)
	if builder.get_child_count() != 2:
		failures.append("both ladder alternatives, and only those cells, must create zones")
	for zone: Node in builder.get_children():
		if not zone.is_in_group("ladder_zone") or (zone as Area2D).collision_layer != 4:
			failures.append("generated zone has wrong group or trigger layer")
		var shape := zone.get_node("CollisionShape2D").shape as RectangleShape2D
		if shape.size != Vector2(8, 8):
			failures.append("generated ladder zone has wrong tile size")
	var first := builder.get_child(0) as Node2D
	if first.global_position != layer.to_global(layer.map_to_local(Vector2i.ZERO)):
		failures.append("generated ladder zone position does not match map_to_local")
	builder.call("rebuild")
	if builder.get_child_count() != 2:
		failures.append("rebuild duplicated or lost ladder zones")
	terrain.free()
	_assert_template_and_room_bake(script, failures)
	return failures


func _assert_template_and_room_bake(script: Script, failures: Array[String]) -> void:
	var template := load("res://scenes/rooms/template/level_template.tscn") as PackedScene
	if template == null:
		failures.append("level template is missing")
		return
	var template_root := template.instantiate()
	if template_root.get_node_or_null("RoomContent/Terrain/LadderAreaBuilder") == null:
		failures.append("level template has no LadderAreaBuilder")
	template_root.free()
	var room_path := "res://scenes/levels/room_01_00.tscn"
	var packed := load(room_path) as PackedScene
	if packed == null:
		failures.append("room_01_00 is missing")
		return
	var preview := packed.instantiate()
	add_child(preview)
	var source_builder := preview.get_node_or_null("RoomContent/Terrain/LadderAreaBuilder")
	if source_builder == null or source_builder.get_script() != script:
		failures.append("room_01_00 did not inherit the ladder builder")
	elif source_builder.get_child_count() == 0:
		failures.append("user ladder tiles did not generate any runtime zones")
	preview.free()
	var source := packed.instantiate()
	var staged: Dictionary = ROOM_BAKER.new().stage(source, room_path)
	if not staged.get("ok", false):
		failures.append("room_01_00 could not stage ladder terrain: %s" % staged.get("errors", []))
	else:
		var terrain := (staged["terrain_scene"] as PackedScene).instantiate()
		var baked_builder := terrain.get_node_or_null("Terrain/LadderAreaBuilder")
		if baked_builder == null:
			failures.append("baked terrain lost ladder builder")
		elif baked_builder.get_child_count() != 0:
			failures.append("runtime ladder zones were serialized into baked terrain")
		add_child(terrain)
		if baked_builder != null and baked_builder.get_child_count() == 0:
			failures.append("baked terrain did not generate zones at runtime")
		terrain.free()
	source.free()
```

Run the focused test. Expected RED: builder/template integration is missing.

- [x] **Step 2: Implement the runtime builder**

```gdscript
class_name LadderTileAreaBuilder
extends Node2D

const LADDER_ZONE := preload("res://addons/platformer_kit/world/entities/ladder_zone.tscn")

@export var source_id := 0
@export var atlas_coordinates := Vector2i(0, 7)


func _ready() -> void:
	rebuild()


func rebuild() -> int:
	for child: Node in get_children():
		child.free()
	var built := 0
	var terrain := get_parent()
	if terrain == null:
		return built
	for candidate: Node in terrain.get_children():
		var layer := candidate as TileMapLayer
		if layer == null or layer.tile_set == null:
			continue
		for cell: Vector2i in layer.get_used_cells():
			if layer.get_cell_source_id(cell) != source_id or layer.get_cell_atlas_coords(cell) != atlas_coordinates:
				continue
			var zone := LADDER_ZONE.instantiate() as Area2D
			var rectangle := RectangleShape2D.new()
			rectangle.size = Vector2(layer.tile_set.tile_size)
			zone.get_node("CollisionShape2D").shape = rectangle
			zone.set_meta("source_cell", cell)
			add_child(zone)
			zone.global_position = global_transform.affine_inverse() * layer.to_global(layer.map_to_local(cell))
			built += 1
	return built
```

- [x] **Step 3: Add the template node without replacing user edits**

Add one external script resource pointing to `res://scripts/world/ladder_tile_area_builder.gd`, using the next unused id (`9_ladder_builder` in the current template). Add after `MarkerTiles`:

```ini
[node name="LadderAreaBuilder" type="Node2D" parent="RoomContent/Terrain"]
script = ExtResource("9_ladder_builder")
```

Run the focused test; source and staged alternatives must pass. Do not hand-edit generated scenes and do not stage the user-modified template wholesale.

- [x] **Step 4: Commit owned code/tests**

```powershell
git add -- scripts/world/ladder_tile_area_builder.gd tests/world/test_ladder_tiles.gd
git diff --cached --check
git commit -m "feat: generate ladder zones from tiles"
```

### Task 4: Player composition and public climb interface

**Files:**
- Modify: `scripts/player/player_controller.gd`
- Modify: `scenes/player/player.tscn`
- Test: `tests/platformer_kit/character/test_ladder_motion.gd`

- [x] **Step 1: Add failing player composition assertions**

Append to `test_ladder_motion.gd` and call it from `run()`:

```gdscript
func _assert_player_composition(failures: Array[String]) -> void:
	var packed := load("res://scenes/player/player.tscn") as PackedScene
	var player := packed.instantiate() as CharacterBody2D
	add_child(player)
	player.set_physics_process(false)
	if player.get_node_or_null("LadderMotion") == null:
		failures.append("player scene is missing LadderMotion")
	if not player.has_method("is_on_ladder") or not player.has_signal("climb_animation_requested"):
		failures.append("player climb animation interface is missing")
	var motion := player.get_node_or_null("LadderMotion")
	if motion != null:
		var zone := (load(ZONE_SCENE_PATH) as PackedScene).instantiate() as Area2D
		add_child(zone)
		(motion.get_node("Detector") as Area2D).area_entered.emit(zone)
		if not bool(player.call("is_on_ladder")):
			failures.append("player did not delegate ladder overlap state")
		player.call("respawn_at", Vector2.ZERO)
		motion.get_node("Detector").area_exited.emit(zone)
		zone.free()
	player.free()
```

Expected RED: `LadderMotion`, `is_on_ladder`, and the public signal are missing.

- [x] **Step 2: Add scene composition**

Add the ladder component as an external script resource and append:

```ini
[node name="LadderMotion" type="Node2D" parent="."]
script = ExtResource("7_ladder_motion")
```

Use the next free resource id and update `load_steps` without changing existing ability/effects nodes.

- [x] **Step 3: Route motion and signals through PlayerController**

Add near the controller signals/exports:

```gdscript
signal climb_animation_requested(active: bool, direction: Vector2)
```

Add onready access:

```gdscript
@onready var _ladder_motion: Node = get_node_or_null("LadderMotion")
@onready var _hero_animation: Node = get_node_or_null("SpriteRoot/HeroAnimation")
```

In `_ready()` add:

```gdscript
	if _ladder_motion != null and _ladder_motion.has_signal("climb_animation_requested"):
		_ladder_motion.connect("climb_animation_requested", _on_climb_animation_requested)
```

Replace the unconditional motor call with:

```gdscript
	var ladder_handled := false
	if _ladder_motion != null:
		ladder_handled = bool(_ladder_motion.call("step", _movement_context, intent, _environment, profile, delta))
	if not ladder_handled:
		_motor.call("step", _movement_context, intent, _environment, profile, delta)
```

Add public/delegate/reset methods:

```gdscript
func is_on_ladder() -> bool:
	return _ladder_motion != null and bool(_ladder_motion.call("is_on_ladder"))


func _on_climb_animation_requested(active: bool, direction: Vector2) -> void:
	climb_animation_requested.emit(active, direction)
	if _hero_animation != null:
		_hero_animation.call("set_climb_state", active, direction)
```

In `set_control_locked(true)` and `respawn_at()` call `_ladder_motion.reset()` when present. Also reset `_hero_animation` when present; Task 5 defines that method.

- [x] **Step 4: Verify GREEN and commit**

Run the ladder and existing motor integration tests; both must exit 0.

```powershell
git add -- scripts/player/player_controller.gd scenes/player/player.tscn tests/platformer_kit/character/test_ladder_motion.gd
git diff --cached --check
git commit -m "feat: compose ladder motion into player"
```

### Task 5: Hero SpriteFrames and animation driver

**Files:**
- Create: `assets/generated/hero.png`
- Create: `scripts/tools/build_hero_sprite_frames.gd`
- Create: `resources/player/hero_sprite_frames.tres`
- Create: `game/player/hero_animation_controller.gd`
- Modify: `scenes/player/player.tscn`
- Modify: `scripts/player/player_controller.gd`
- Test: `tests/player/test_hero_animation.gd`

- [x] **Step 1: Write failing resource/state tests**

Create `test_hero_animation.gd` with this complete content:

```gdscript
extends Node

const DRIVER_PATH := "res://game/player/hero_animation_controller.gd"
const FRAMES_PATH := "res://resources/player/hero_sprite_frames.tres"
const ROWS := [
	["idle", 0, 2, 2.0, true], ["walk", 1, 4, 8.0, true],
	["run", 2, 4, 12.0, true], ["jump", 3, 2, 10.0, false],
	["fall", 4, 2, 6.0, true], ["climb", 5, 2, 8.0, true],
	["look_up", 6, 1, 1.0, false], ["look_down", 7, 1, 1.0, false],
	["look_left", 8, 1, 1.0, false], ["look_right", 9, 1, 1.0, false],
]


func run() -> Array[String]:
	var failures: Array[String] = []
	var frames := load(FRAMES_PATH) as SpriteFrames
	if frames == null:
		return ["Hero SpriteFrames resource is missing"]
	_assert_frames(frames, failures)
	var driver := _make_driver(frames)
	if driver == null:
		failures.append("Hero animation driver is missing")
		return failures
	var state := _state(true, Vector2.ZERO)
	state.vertical_axis = -1.0
	driver.call("update_visual", 0.0, state)
	if driver.call("get_current_animation") != "look_up":
		failures.append("ground W did not select look_up")
	state.vertical_axis = 1.0
	driver.call("update_visual", 0.0, state)
	if driver.call("get_current_animation") != "look_down":
		failures.append("ground S did not select look_down")
	state = _state(true, Vector2(-20, 0), -1)
	driver.call("update_visual", 0.0, state)
	if driver.call("get_current_animation") != "walk" or not bool(driver.get_node("AnimatedSprite2D").flip_h):
		failures.append("walk speed or generic left flip is wrong")
	state.velocity.x = -90.0
	driver.call("update_visual", 0.0, state)
	if driver.call("get_current_animation") != "run":
		failures.append("run threshold did not select run")
	state = _state(false, Vector2(0, -10), 1)
	driver.call("update_visual", 0.0, state)
	if driver.call("get_current_animation") != "jump":
		failures.append("upward airborne velocity did not select jump")
	state.velocity.y = 10.0
	driver.call("update_visual", 0.0, state)
	if driver.call("get_current_animation") != "fall":
		failures.append("downward airborne velocity did not select fall")
	state = _state(true, Vector2.ZERO, 1)
	driver.call("update_visual", 1.99, state)
	if driver.call("get_current_animation") != "look_right":
		failures.append("idle breathing started before two seconds")
	driver.call("update_visual", 0.02, state)
	if driver.call("get_current_animation") != "idle":
		failures.append("two-second idle breathing did not start")
	state.facing = -1
	driver.call("reset")
	driver.call("update_visual", 0.0, state)
	if driver.call("get_current_animation") != "look_left" or bool(driver.get_node("AnimatedSprite2D").flip_h):
		failures.append("dedicated look_left was incorrectly flipped")
	driver.call("set_climb_state", true, Vector2(0, -1))
	state = _state(false, Vector2(0, -10), 1)
	driver.call("update_visual", 0.0, state)
	if driver.call("get_current_animation") != "climb":
		failures.append("W climb did not take priority over jump")
	driver.call("set_climb_state", true, Vector2(0, 1))
	state.velocity.y = 50.0
	driver.call("update_visual", 0.0, state)
	if driver.call("get_current_animation") != "climb":
		failures.append("S climb did not take priority over fall")
	driver.call("set_climb_state", true, Vector2.ZERO)
	state.velocity = Vector2.ZERO
	driver.call("update_visual", 2.1, state)
	if driver.call("get_current_animation") != "idle":
		failures.append("neutral ladder contact incorrectly selected fall or blocked idle")
	driver.call("set_climb_state", false, Vector2.ZERO)
	state.velocity.y = -100.0
	state.just_jumped = true
	driver.call("update_visual", 0.0, state)
	var sprite := driver.get_node("AnimatedSprite2D") as AnimatedSprite2D
	sprite.frame = 1
	driver.call("update_visual", 0.0, state)
	if driver.call("get_current_animation") != "jump" or sprite.frame != 0:
		failures.append("repeated jump did not restart the jump animation")
	driver.call("reset")
	if driver.call("get_current_animation") != "" or float(driver.get("_idle_elapsed")) != 0.0:
		failures.append("Hero reset retained stale animation state")
	driver.free()
	_assert_player_scene(failures)
	return failures


func _state(grounded: bool, velocity: Vector2, facing: int = 1) -> Dictionary:
	return {
		"grounded": grounded, "velocity": velocity, "move_axis": 0.0,
		"vertical_axis": 0.0, "facing": facing, "just_jumped": false,
	}


func _make_driver(frames: SpriteFrames) -> Node2D:
	var script := load(DRIVER_PATH) as Script
	if script == null:
		return null
	var driver := script.new() as Node2D
	var sprite := AnimatedSprite2D.new()
	sprite.name = "AnimatedSprite2D"
	sprite.sprite_frames = frames
	driver.add_child(sprite)
	add_child(driver)
	return driver


func _assert_frames(frames: SpriteFrames, failures: Array[String]) -> void:
	for row: Array in ROWS:
		var animation := StringName(row[0])
		if not frames.has_animation(animation):
			failures.append("missing Hero animation: %s" % animation)
			continue
		if frames.get_frame_count(animation) != int(row[2]):
			failures.append("wrong frame count: %s" % animation)
		if not is_equal_approx(frames.get_animation_speed(animation), float(row[3])):
			failures.append("wrong animation speed: %s" % animation)
		if frames.get_animation_loop(animation) != bool(row[4]):
			failures.append("wrong loop setting: %s" % animation)
		for column: int in range(row[2]):
			var texture := frames.get_frame_texture(animation, column) as AtlasTexture
			if texture == null or texture.region != Rect2(column * 10, row[1] * 10, 10, 10):
				failures.append("wrong atlas region: %s frame %d" % [animation, column])


func _assert_player_scene(failures: Array[String]) -> void:
	var player := (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	for path: String in ["SpriteRoot/Block", "SpriteRoot/MeshInstance2D", "SpriteRoot/MeshInstance2D2"]:
		var placeholder := player.get_node_or_null(path) as CanvasItem
		if placeholder == null or placeholder.visible:
			failures.append("old placeholder must be hidden: %s" % path)
	var sprite := player.get_node_or_null("SpriteRoot/HeroAnimation/AnimatedSprite2D") as AnimatedSprite2D
	if sprite == null or sprite.position != Vector2(0, -5):
		failures.append("Hero sprite or feet anchor is missing")
	if player.get_node_or_null("LadderMotion") == null:
		failures.append("player lost LadderMotion during Hero composition")
	player.free()
```

Expected RED: SpriteFrames, Hero driver, and Hero scene composition are missing.

- [x] **Step 2: Copy the supplied asset and add a repeatable frame generator**

Copy only if the destination does not exist:

```powershell
$source = 'D:\Godot4\GodotProject\wellwell-b\assets\generated\hero.png'
$target = 'D:\Godot4\GodotProject\wellwell\assets\generated\hero.png'
if (Test-Path -LiteralPath $target) { throw "Refusing to overwrite $target" }
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $target) | Out-Null
Copy-Item -LiteralPath $source -Destination $target
```

`build_hero_sprite_frames.gd`:

```gdscript
extends SceneTree

const OUTPUT := "res://resources/player/hero_sprite_frames.tres"
const ROWS := [
	["idle", 0, 2, 2.0, true], ["walk", 1, 4, 8.0, true],
	["run", 2, 4, 12.0, true], ["jump", 3, 2, 10.0, false],
	["fall", 4, 2, 6.0, true], ["climb", 5, 2, 8.0, true],
	["look_up", 6, 1, 1.0, false], ["look_down", 7, 1, 1.0, false],
	["look_left", 8, 1, 1.0, false], ["look_right", 9, 1, 1.0, false],
]


func _init() -> void:
	var image := load("res://assets/generated/hero.png") as Texture2D
	if image == null or image.get_size() != Vector2(80, 100):
		push_error("hero.png must be an 80x100 texture")
		quit(1)
		return
	var frames := SpriteFrames.new()
	frames.remove_animation("default")
	for row: Array in ROWS:
		var animation := StringName(row[0])
		frames.add_animation(animation)
		frames.set_animation_speed(animation, row[3])
		frames.set_animation_loop(animation, row[4])
		for column: int in range(row[2]):
			var frame := AtlasTexture.new()
			frame.atlas = image
			frame.region = Rect2(column * 10, row[1] * 10, 10, 10)
			frames.add_frame(animation, frame)
	var error := ResourceSaver.save(frames, OUTPUT)
	if error != OK:
		push_error("could not save Hero SpriteFrames: %s" % error_string(error))
	quit(0 if error == OK else 1)
```

First import the copied texture, then run the generator (the runtime loader needs Godot's imported `.ctex`):

```powershell
& $godot --headless --editor --path . --import --quit
& $godot --headless --path . -s res://scripts/tools/build_hero_sprite_frames.gd
```

- [x] **Step 3: Implement HeroAnimationController**

```gdscript
class_name HeroAnimationController
extends Node2D

@export var run_threshold := 85.0
@export var idle_delay := 2.0

@onready var _sprite: AnimatedSprite2D = $AnimatedSprite2D

var _climb_active := false
var _climb_direction := Vector2.ZERO
var _idle_elapsed := 0.0
var _current := ""
var _facing := 1


func set_climb_state(active: bool, direction: Vector2) -> void:
	_climb_active = active
	_climb_direction = direction
	_idle_elapsed = 0.0


func reset() -> void:
	_climb_active = false
	_climb_direction = Vector2.ZERO
	_idle_elapsed = 0.0
	_current = ""
	_facing = 1
	_sprite.stop()
	_sprite.flip_h = false


func get_current_animation() -> String:
	return _current


func update_visual(delta: float, state: Dictionary) -> void:
	var grounded := bool(state.get("grounded", false))
	var velocity := Vector2(state.get("velocity", Vector2.ZERO))
	var move_axis := float(state.get("move_axis", 0.0))
	var vertical_axis := float(state.get("vertical_axis", 0.0))
	var just_jumped := bool(state.get("just_jumped", false))
	_facing = int(state.get("facing", _facing))
	var horizontal_speed := absf(velocity.x)
	var has_input := absf(move_axis) > 0.01 or absf(vertical_axis) > 0.01
	var has_motion := horizontal_speed >= 1.0 or (_climb_active and not _climb_direction.is_zero_approx())
	if has_input or has_motion or just_jumped or (not grounded and not _climb_active):
		_idle_elapsed = 0.0
	else:
		_idle_elapsed += maxf(delta, 0.0)
	var target := ""
	if _climb_active and absf(_climb_direction.y) > 0.01:
		target = "climb"
	elif not grounded and not _climb_active:
		target = "jump" if velocity.y < 0.0 else "fall"
	elif grounded and absf(vertical_axis) > 0.01:
		target = "look_up" if vertical_axis < 0.0 else "look_down"
	elif horizontal_speed >= 1.0:
		target = "run" if horizontal_speed >= run_threshold else "walk"
	elif _idle_elapsed >= idle_delay:
		target = "idle"
	else:
		target = "look_left" if _facing < 0 else "look_right"
	_play(target, just_jumped and target == "jump")


func _play(target: String, restart: bool) -> void:
	if target != _current or restart:
		_current = target
		_sprite.play(StringName(target))
	_sprite.flip_h = _facing < 0 and not target.begins_with("look_")
```

- [x] **Step 4: Compose Hero and route visual state**

In `player.tscn`, hide the three old visual nodes, add Hero controller and LadderMotion resources, and add:

```ini
[node name="HeroAnimation" type="Node2D" parent="SpriteRoot"]
script = ExtResource("8_hero_animation")

[node name="AnimatedSprite2D" type="AnimatedSprite2D" parent="SpriteRoot/HeroAnimation"]
position = Vector2(0, -5)
sprite_frames = ExtResource("9_hero_frames")
animation = &"idle"
```

Task 4 has already added `7_ladder_motion`; use `8_hero_animation` and `9_hero_frames` for the two new resources and set `load_steps=11`. Keep that existing `LadderMotion` node unchanged.

After the existing physics state is updated, call:

```gdscript
	if _hero_animation != null:
		_hero_animation.call("update_visual", delta, {
			"grounded": is_on_floor(), "velocity": velocity,
			"move_axis": intent.move_axis, "vertical_axis": intent.vertical_axis,
			"facing": facing, "just_jumped": _movement_context.just_jumped,
		})
```

Keep positive X squash in `respawn_at`, `_recover_visual`, and `_play_jump_intent_feedback`: use `Vector2.ONE`, `Vector2.ONE`, and `Vector2(1.08,0.92)` respectively. `_update_facing()` must no longer flip `SpriteRoot`; HeroAnimationController handles generic flips and dedicated look rows.

- [x] **Step 5: Verify GREEN and commit**

Run Hero, ladder, player-effects, and motor integration tests; all must exit 0.

```powershell
git add -- assets/generated/hero.png scripts/tools/build_hero_sprite_frames.gd resources/player/hero_sprite_frames.tres game/player/hero_animation_controller.gd scenes/player/player.tscn scripts/player/player_controller.gd tests/player/test_hero_animation.gd
git diff --cached --check
git commit -m "feat: animate hero movement and climbing"
```

### Task 6: Bake, documentation, and final verification

**Files:**
- Create: `scripts/tools/rebake_room.gd`
- Create: `docs/ladders.md`
- Modify: `tests/runtime_suite.gd`
- Generated by RoomBaker only: `scenes/rooms/generated/room_01_00/` and `resources/rooms/generated/room_01_00.tres`

- [x] **Step 1: Register the three new test scripts**

Append to `TESTS`:

```gdscript
	preload("res://tests/platformer_kit/character/test_ladder_motion.gd"),
	preload("res://tests/world/test_ladder_tiles.gd"),
	preload("res://tests/player/test_hero_animation.gd"),
```

- [x] **Step 2: Add the targeted rebake runner**

```gdscript
extends SceneTree

const ROOM_BAKER := preload("res://addons/world_editor/authoring/room/room_baker.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 1:
		push_error("usage: -- res://scenes/levels/room_01_00.tscn")
		quit(2)
		return
	var packed := load(args[0]) as PackedScene
	if packed == null:
		push_error("could not load source room")
		quit(1)
		return
	var source := packed.instantiate()
	var result: Dictionary = ROOM_BAKER.new().bake(source, args[0])
	source.free()
	if not result.get("ok", false):
		push_error("room bake failed: %s" % str(result.get("errors", [])))
		quit(1)
		return
	quit(0)
```

Run:

```powershell
& $godot --headless --path . -s res://scripts/tools/rebake_room.gd -- res://scenes/levels/room_01_00.tscn
& $godot --headless --path . --import
```

Expected: exit 0. Reload the baked terrain in `test_ladder_tiles.gd` and assert it contains `Terrain/LadderAreaBuilder`. Review the generated diff; never replace the user's source tile layout.

- [x] **Step 3: Document authoring and Hero animation**

Write `docs/ladders.md` with:

- Put `(0,7)` on any terrain TileMapLayer; alternative 0 and 1 share behavior.
- W/S climb, direction keys move freely, repeated Jump climbs quickly, S+Jump fast-drops until ground/exit/W.
- `climb_animation_requested(active,direction)` and `is_on_ladder()` public API.
- Hero animation rows, 85 px/s run threshold, 2-second idle, and no double-flip rule.
- Re-bake command from Task 6 Step 2; do not edit generated terrain manually.
- Focused test commands for all three new test files.

- [x] **Step 4: Run runtime and regression verification**

Run all three new tests, existing input/profile/motor/player-effects/Killzone/movement-lab tests, the full suite, and:

```powershell
& $godot --headless --path . --quit-after 120 res://scenes/levels/room_01_00.tscn
& $godot --headless --path . --quit-after 120 res://scenes/app/main.tscn
git diff --check
```

Expected: all focused tests and both scene runs exit 0; full suite has no new failure beyond the recorded SavePoint baseline. Request an independent code review, fix Critical/Important findings, and rerun the affected tests.

- [x] **Step 5: Commit owned integration files**

```powershell
git add -- scripts/tools/rebake_room.gd docs/ladders.md docs/superpowers/plans/2026-11-15-ladder-climbing.md tests/runtime_suite.gd
git diff --cached --check
git commit -m "docs: add ladder authoring and animation guide"
```

Leave user-owned source tiles/maps/template modifications unstaged, and report the intentional working-tree state rather than committing them wholesale.

## Execution Result

- Implemented vertical intent, climb tuning, ladder zones, free/repeated jumping, S climb, S+Jump latched fast drop, player composition, alternative-tile scanning, and the 20-frame Hero animation driver.
- Source `room_01_00` and its baked terrain both generate ladder zones at runtime. A regression test uses a 320 px non-zero room origin to prove world alignment.
- RoomBaker preserves text UIDs in headless mode, commits UID mappings only after successful installation, and captures/restores output UID mappings during rollback. Tests cover repeated bakes, conflicts, validation failures, and injected installation failure.
- Hero tests cover all atlas regions, animation priority, direction flips, climb idle, the 85 px/s run threshold, 2-second idle breathing, and repeated jump restart.
- Input/profile/ladder/tile/Hero/RoomBaker/player-effects/Killzone/motor/movement-lab/template tests all exit 0. Source room and main scene also exit 0.
- The full suite still exits 1 only for the pre-existing `SavePoint/VisualRoot` versus `Visual` mismatch. UID cache warnings were eliminated by preserving UIDs and running the documented `--import` refresh after headless baking.
- The user-owned source tiles, maps, template debug additions, and generated room outputs remain uncommitted in the working tree rather than being mixed wholesale into feature commits.
