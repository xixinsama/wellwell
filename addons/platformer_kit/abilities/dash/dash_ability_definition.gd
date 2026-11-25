class_name DashAbilityDefinition
extends "res://addons/platformer_kit/abilities/runtime/ability_definition.gd"

const DASH_RUNTIME := preload("res://addons/platformer_kit/abilities/dash/dash_ability_runtime.gd")

@export_range(0.0, 2000.0, 1.0, "or_greater") var dash_speed := 240.0
@export_range(0.01, 5.0, 0.01, "or_greater") var dash_duration := 0.15
## Hit-stop at dash start. The player freezes the whole gameplay tree for this
## long before the dash begins to move.
@export_range(0.0, 1.0, 0.01) var freeze_seconds := 0.05
## Speed kept after the dash ends, so momentum survives the state transition.
@export_range(0.0, 2000.0, 1.0, "or_greater") var end_speed := 160.0
## Window after dash start in which a jump becomes a super, hyper, wavedash or
## wallbounce. It intentionally outlives the dash itself.
@export_range(0.0, 2.0, 0.01) var dash_attack_seconds := 0.3
## Ground refill is suppressed for this long after a dash starts.
@export_range(0.0, 2.0, 0.01) var refill_cooldown_seconds := 0.1

## Read the vertical input too, so the dash can go up, down and diagonally.
## Off keeps the legacy horizontal-only dash.
@export var eight_directional := true
## Input shorter than this falls back to the facing direction instead of dashing.
@export_range(0.0, 1.0, 0.01) var direction_deadzone := 0.35
## How many dashes are stored before refilling, like a jump count. 0 means
## unlimited dashes; the ability runtime exposes refill() for the game to call
## when the character touches the ground or swims.
@export_range(0, 9, 1) var max_charges := 1
## Snap the dash to this angle step (45 keeps the eight directions crisp and
## gives diagonals the same speed as straight dashes). 0 disables snapping.
@export_range(0.0, 90.0, 1.0) var direction_snap_degrees := 45.0


func _init() -> void:
    ability_id = &"dash"
    runtime_script = DASH_RUNTIME
