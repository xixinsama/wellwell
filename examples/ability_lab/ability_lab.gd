extends Node2D

@onready var player: CharacterBody2D = $Player
@onready var controller: Node = $Player/AbilityLoadout/AbilityController
@onready var status: Label = $Status


func _ready() -> void:
    _update_status()


func _process(_delta: float) -> void:
    _update_status()


func _update_status() -> void:
    var runtime := controller.call("get_runtime", &"dash") as RefCounted
    var state := "LOCKED"
    var cooldown := 0.0
    if runtime != null:
        cooldown = float(runtime.get("cooldown_remaining"))
        if bool(runtime.get("active")):
            state = "ACTIVE"
        elif cooldown > 0.0:
            state = "COOLDOWN"
        else:
            state = "READY"
    status.text = "Dash: %s\nCooldown: %.2f\nSpeed: %.1f" % [
        state,
        cooldown,
        player.velocity.length(),
    ]
