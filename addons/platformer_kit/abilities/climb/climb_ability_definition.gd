class_name ClimbAbilityDefinition
extends AbilityDefinition

## Passive wall-movement unlock. PlayerController checks this ability before it
## enters WALL_GRAB / WALL_SLIDE, so grab, climb, wall slide, wall jump and
## wallbounce all become available together when the pickup is collected.


func _init() -> void:
    ability_id = &"climb"
