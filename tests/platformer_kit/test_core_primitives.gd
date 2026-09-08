extends Node

const STATE_MACHINE_PATH := "res://addons/platformer_kit/core/state/state_machine.gd"
const GAME_EVENT_PATH := "res://addons/platformer_kit/core/events/game_event.gd"
const EVENT_BUS_PATH := "res://addons/platformer_kit/core/events/scoped_event_bus.gd"
const TAG_CONTAINER_PATH := "res://addons/platformer_kit/core/tags/tag_container.gd"


func run() -> Array[String]:
	var failures: Array[String] = []
	for path: String in [STATE_MACHINE_PATH, GAME_EVENT_PATH, EVENT_BUS_PATH, TAG_CONTAINER_PATH]:
		if not ResourceLoader.exists(path, "Script"):
			failures.append("Platformer Kit core script is missing: %s" % path)
	if not failures.is_empty():
		return failures
	_assert_state_machine(failures)
	_assert_scoped_event_bus(failures)
	_assert_tag_container(failures)
	return failures


func _assert_state_machine(failures: Array[String]) -> void:
	var machine: RefCounted = (load(STATE_MACHINE_PATH) as Script).new()
	var events: Array[String] = []
	machine.connect("state_changed", func(previous: StringName, current: StringName) -> void:
		events.append("signal:%s>%s" % [previous, current])
	)
	machine.call("add_state", &"idle", func() -> void: events.append("enter:idle"), func() -> void: events.append("exit:idle"))
	machine.call("add_state", &"run", func() -> void: events.append("enter:run"), func() -> void: events.append("exit:run"))
	if not bool(machine.call("transition_to", &"idle")):
		failures.append("StateMachine rejected a registered initial state")
	events.clear()
	if not bool(machine.call("transition_to", &"run")):
		failures.append("StateMachine rejected a registered transition")
	if events != ["exit:idle", "enter:run", "signal:idle>run"]:
		failures.append("StateMachine transition order is not exit, enter, signal")
	if bool(machine.call("transition_to", &"missing")) or machine.get("current_state") != &"run":
		failures.append("StateMachine accepted an unknown state or changed current state")


func _assert_scoped_event_bus(failures: Array[String]) -> void:
	var bus: RefCounted = (load(EVENT_BUS_PATH) as Script).new()
	var received: Array[int] = []
	var first := func(event: RefCounted) -> void: received.append(int(event.get("payload")["value"]))
	var second := func(_event: RefCounted) -> void: received.append(2)
	if not bool(bus.call("subscribe", &"jump", first)) or bool(bus.call("subscribe", &"jump", first)):
		failures.append("ScopedEventBus did not reject a duplicate subscription")
	bus.call("subscribe", &"jump", second)
	var event: RefCounted = (load(GAME_EVENT_PATH) as Script).new(&"jump", {"value": 1})
	bus.call("publish", event)
	if received != [1, 2]:
		failures.append("ScopedEventBus did not publish in subscription order")
	if not bool(bus.call("unsubscribe", &"jump", first)):
		failures.append("ScopedEventBus could not unsubscribe a registered callback")
	received.clear()
	bus.call("publish", event)
	if received != [2]:
		failures.append("ScopedEventBus invoked an unsubscribed callback")


func _assert_tag_container(failures: Array[String]) -> void:
	var tags: RefCounted = (load(TAG_CONTAINER_PATH) as Script).new()
	if not bool(tags.call("add", &"grounded")) or bool(tags.call("add", &"grounded")):
		failures.append("TagContainer did not report duplicate insertion")
	tags.call("add", &"player")
	if not bool(tags.call("has_all", [&"grounded", &"player"])):
		failures.append("TagContainer did not match all stored tags")
	if not bool(tags.call("remove", &"grounded")) or bool(tags.call("has", &"grounded")):
		failures.append("TagContainer did not remove a stored tag")
