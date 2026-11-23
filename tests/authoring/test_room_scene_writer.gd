extends Node

## Coverage for the inherited room-scene writer used by the New Room wizard.

const WRITER := preload("res://addons/world_editor/authoring/world/room_scene_writer.gd")
const TEMPLATE := "res://scenes/rooms/template/level_template.tscn"
const PATH := "user://writer_room.tscn"
const SECOND_PATH := "user://writer_room_2.tscn"
const BAD_PATH := "user://writer_room_bad.tscn"


func run() -> Array[String]:
    var failures: Array[String] = []
    _cleanup()
    var result: Dictionary = WRITER.write_inherited_scene(PATH, TEMPLATE, "writer_room", "Writer Room")
    if not bool(result.get("ok", false)):
        failures.append("writer failed: %s" % [result.get("errors", [])])
    else:
        _assert_written_scene(failures)
    var second: Dictionary = WRITER.write_inherited_scene(SECOND_PATH, TEMPLATE, "writer_room_2")
    if not bool(second.get("ok", false)):
        failures.append("writer failed without a display name: %s" % [second.get("errors", [])])
    else:
        var packed := load(SECOND_PATH) as PackedScene
        var root := null if packed == null else packed.instantiate()
        if root == null:
            failures.append("default-name scene could not load")
        else:
            if String(root.get("display_name")) != "writer_room_2":
                failures.append("display name did not default to the room id")
            root.free()
    if bool(WRITER.write_inherited_scene(BAD_PATH, TEMPLATE, "bad id").get("ok", true)):
        failures.append("writer accepted an invalid room id")
    if bool(WRITER.write_inherited_scene(PATH, TEMPLATE, "writer_room").get("ok", true)):
        failures.append("writer overwrote an existing room source")
    if bool(WRITER.write_inherited_scene("user://writer_room_3.tscn", "res://missing_template.tscn", "writer_3").get("ok", true)):
        failures.append("writer accepted a missing template")
    _cleanup()
    return failures


func _assert_written_scene(failures: Array[String]) -> void:
    var packed := load(PATH) as PackedScene
    if packed == null:
        failures.append("written room scene could not load")
        return
    var root := packed.instantiate()
    if root == null:
        failures.append("written room scene could not instantiate")
        return
    if String(root.get("room_id")) != "writer_room":
        failures.append("written room scene has the wrong room_id")
    if String(root.get("display_name")) != "Writer Room":
        failures.append("written room scene has the wrong display_name")
    if root.get_node_or_null("RoomContent/Entities/StartSpawn") == null:
        failures.append("written room scene did not inherit the template entities")
    if root.get_node_or_null("PreviewOnly/Player") == null:
        failures.append("written room scene did not inherit the template preview children")
    root.free()


func _cleanup() -> void:
    for path in [PATH, SECOND_PATH, BAD_PATH, "user://writer_room_3.tscn"]:
        DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
