extends Node

const INTERACTABLE_PATH := "res://addons/platformer_kit/interaction/interactable.gd"
const DETECTOR_PATH := "res://addons/platformer_kit/interaction/interaction_detector.gd"


func run() -> Array[String]:
	var failures: Array[String] = []
	var interactable_script := load(INTERACTABLE_PATH) as Script
	var detector_script := load(DETECTOR_PATH) as Script
	if interactable_script == null or detector_script == null:
		return ["interaction scripts could not be loaded"]

	var detector: Area2D = detector_script.new()
	var low: Area2D = interactable_script.new()
	low.interaction_id = &"low"
	low.interaction_priority = 1
	var high: Area2D = interactable_script.new()
	high.interaction_id = &"high"
	high.interaction_priority = 10
	detector.register_candidate(low)
	detector.register_candidate(high)
	if detector.get_best_candidate() != high:
		failures.append("InteractionDetector did not select the highest-priority candidate")
	high.enabled = false
	if detector.get_best_candidate() != low:
		failures.append("InteractionDetector selected a disabled candidate")
	var actor := Node.new()
	if not detector.interact(actor):
		failures.append("InteractionDetector did not invoke the available candidate")
	detector.unregister_candidate(low)
	if detector.get_best_candidate() != null:
		failures.append("InteractionDetector retained a removed candidate")
	actor.free()
	detector.free()
	low.free()
	high.free()
	return failures
