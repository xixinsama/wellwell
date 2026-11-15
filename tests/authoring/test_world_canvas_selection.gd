extends Node

## Coverage for the World canvas selection model: box selection (intersection),
## additive/toggle selection, group drag (one command) and delete/escape input.

const CANVAS := preload("res://addons/world_editor/world_layout_canvas.gd")
const WORLD := preload("res://addons/platformer_kit/world/data/world_data.gd")
const ROOM := preload("res://addons/platformer_kit/world/data/room_data.gd")


class FakeMain:
    extends Control

    var world_data: Resource
    var selected_room_id := ""
    var moves: Array = []
    var move_calls := 0

    func select_room(room_id: String) -> void:
        selected_room_id = room_id

    func move_rooms_by(delta: Vector2i) -> bool:
        move_calls += 1
        moves.append(delta)
        return true

    func move_room(room_id: String, origin: Vector2i) -> bool:
        move_calls += 1
        moves.append([room_id, origin])
        return true

    func update_zoom_label(_zoom: float) -> void:
        pass


func run() -> Array[String]:
    var failures: Array[String] = []
    var main := FakeMain.new()
    main.world_data = _make_world()
    var canvas := CANVAS.new() as Control
    canvas.size = Vector2(800, 600)
    add_child(canvas)
    canvas.call("set_main_screen", main)
    canvas.call("focus_all")

    var alpha_rect: Rect2 = canvas.call("_room_rect", Vector2i(0, 0), Vector2i(2, 1))
    var beta_rect: Rect2 = canvas.call("_room_rect", Vector2i(3, 0), Vector2i(2, 1))

    canvas.call("box_select", alpha_rect.grow(-2.0), false)
    _assert_selection(canvas, ["alpha"], "alpha", failures, "single box")
    canvas.call("box_select", alpha_rect.merge(beta_rect).grow(-2.0), false)
    _assert_selection(canvas, ["alpha", "beta"], "alpha", failures, "both rooms box")
    canvas.call("box_select", alpha_rect.grow(-2.0), false)
    canvas.call("box_select", beta_rect.grow(-2.0), true)
    _assert_selection(canvas, ["alpha", "beta"], "alpha", failures, "additive box")
    canvas.call("_toggle_room", "beta")
    _assert_selection(canvas, ["alpha"], "alpha", failures, "toggle off")
    canvas.call("_toggle_room", "beta")
    _assert_selection(canvas, ["alpha", "beta"], "beta", failures, "toggle on")
    canvas.call("select_all")
    _assert_selection(canvas, ["alpha", "beta"], "alpha", failures, "select all")

    _assert_group_drag(canvas, main, alpha_rect, failures)
    _assert_input_signals(canvas, failures)

    canvas.free()
    main.free()
    return failures


func _assert_group_drag(canvas: Control, main: FakeMain, alpha_rect: Rect2, failures: Array[String]) -> void:
    canvas.call("select_all")
    main.move_calls = 0
    main.moves.clear()
    var start := alpha_rect.get_center()
    var zoom := float(canvas.call("get_zoom"))
    var target := start + Vector2(320.0 * zoom, 0.0)
    if not bool(canvas.call("begin_room_drag", "alpha", start)):
        failures.append("group drag did not start")
        return
    canvas.call("update_room_drag", target)
    canvas.call("_commit_drag", target)
    if main.move_calls != 1:
        failures.append("group drag issued %d move calls instead of one" % main.move_calls)
    elif main.moves.is_empty() or main.moves[0] != Vector2i(1, 0):
        failures.append("group drag moved by %s instead of (1, 0)" % [main.moves])


func _assert_input_signals(canvas: Control, failures: Array[String]) -> void:
    var deleted := [0]
    canvas.delete_requested.connect(func() -> void: deleted[0] += 1)
    var delete_event := InputEventKey.new()
    delete_event.keycode = KEY_DELETE
    delete_event.pressed = true
    canvas.call("_gui_input", delete_event)
    if deleted[0] != 1:
        failures.append("Delete key did not request a removal")
    canvas.call("select_all")
    var cleared := [false]
    canvas.selection_changed.connect(func(ids: Array, _primary: String) -> void:
        if ids.is_empty():
            cleared[0] = true
    )
    var escape_event := InputEventKey.new()
    escape_event.keycode = KEY_ESCAPE
    escape_event.pressed = true
    canvas.call("_gui_input", escape_event)
    if not cleared[0]:
        failures.append("Escape did not emit an empty selection")
    if not (canvas.call("get_selected_room_ids") as Array).is_empty():
        failures.append("Escape did not clear the canvas selection")


func _assert_selection(
    canvas: Control,
    expected: Array,
    primary: String,
    failures: Array[String],
    label: String
) -> void:
    var ids: Array = canvas.call("get_selected_room_ids")
    if ids != expected:
        failures.append("%s: selection was %s, expected %s" % [label, ids, expected])
    if String(canvas.call("get_primary_room_id")) != primary:
        failures.append("%s: primary was %s, expected %s" % [label, canvas.call("get_primary_room_id"), primary])


func _make_world() -> Resource:
    var world := WORLD.new() as Resource
    for entry: Array in [["alpha", Vector2i(0, 0)], ["beta", Vector2i(3, 0)]]:
        var room := ROOM.new() as Resource
        room.room_id = String(entry[0])
        room.room_size_chunks = Vector2i(2, 1)
        world.rooms.append(room)
        world.set_room_origin_chunk(String(entry[0]), entry[1] as Vector2i)
    world.start_room_id = "alpha"
    return world
