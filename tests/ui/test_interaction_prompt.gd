extends Node

const PROMPT_SCENE := preload("res://scenes/ui/interaction_prompt.tscn")


class FakeController extends Node:
	var available := true
	var candidate: Node2D

	func is_available() -> bool:
		return available

	func get_candidate() -> Node:
		return candidate


func run() -> Array[String]:
	var failures: Array[String] = []
	var actor := Node2D.new()
	actor.name = "FakePlayer"
	var controller := FakeController.new()
	controller.name = "InteractionController"
	actor.add_child(controller)
	actor.add_to_group(&"player")
	add_child(actor)
	var target := Node2D.new()
	target.position = Vector2(120.0, 90.0)
	add_child(target)
	var prompt := PROMPT_SCENE.instantiate() as Control
	add_child(prompt)
	prompt.call("bind_actor", actor)

	controller.candidate = target
	prompt.call("_process", 0.0)
	if not prompt.visible:
		failures.append("interaction prompt did not show for a candidate")
	if String(prompt.call("get_displayed_glyph")) != "E":
		failures.append(
			"interaction prompt did not show the keyboard binding: %s"
			% prompt.call("get_displayed_glyph")
		)

	controller.candidate = null
	prompt.call("_process", 0.0)
	if prompt.visible:
		failures.append("interaction prompt stayed visible without a candidate")

	controller.available = false
	controller.candidate = target
	prompt.call("_process", 0.0)
	if prompt.visible:
		failures.append("interaction prompt ignored an unavailable controller")

	controller.available = true
	var pad_event := InputEventJoypadButton.new()
	pad_event.button_index = JOY_BUTTON_X
	pad_event.pressed = true
	prompt.call("_input", pad_event)
	prompt.call("_process", 0.0)
	if String(prompt.call("get_displayed_glyph")) != "X":
		failures.append(
			"interaction prompt did not switch to the gamepad glyph: %s"
			% prompt.call("get_displayed_glyph")
		)

	prompt.queue_free()
	actor.queue_free()
	target.queue_free()
	return failures
