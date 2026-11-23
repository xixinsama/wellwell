extends Node

const ELEVATOR: Script = preload("res://addons/platformer_kit/platforms/components/elevator_motion_component_2d.gd")


func run() -> Array[String]:
	var failures: Array[String] = []
	var lift: Node = ELEVATOR.new()
	lift.set("travel", Vector2(0, -100))
	lift.set("speed", 50)
	lift.set("top_wait_seconds", 0.2)
	lift.set("bottom_wait_seconds", 0.1)
	if lift.call("sample_velocity", 0.1) != Vector2.ZERO:
		failures.append("elevator moved before a rider arrived")
	if not bool(lift.call("activate")):
		failures.append("elevator refused the first rider")
	if bool(lift.call("activate")):
		failures.append("elevator restarted while already moving")
	var highest := 0.0
	for step in 40:
		lift.call("sample_velocity", 0.1)
		highest = minf(highest, Vector2(lift.call("get_offset")).y)
	if absf(highest + 100.0) > 1.0:
		failures.append("elevator did not reach its travel offset: %s" % highest)
	var lowest := 0.0
	for step in 60:
		lift.call("sample_velocity", 0.1)
		lowest = maxf(lowest, Vector2(lift.call("get_offset")).y)
	if absf(lowest) > 1.0:
		failures.append("elevator did not return to its base: %s" % lowest)
	if not bool(lift.call("activate")):
		failures.append("elevator refused a rider after returning")
	lift.free()
	return failures
