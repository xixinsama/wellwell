class_name WorldRoomSceneWriter
extends RefCounted

## Writes a new room source as an **inherited scene** of the level template.
##
## The template keeps its instanced children (player, debug HUD, camera) because
## the new file only overrides the root's room_id / display_name. This is the
## same shape as the hand-authored room scenes, so the editor and the room
## contract treat it as a first-class source scene.
##
## Messages are English by project convention (core/editor errors are not
## translated).

const TEMPLATE_SETTING := "world_editor/room_template_scene"


static func write_inherited_scene(
    path: String,
    template_path: String,
    room_id: String,
    display_name: String = ""
) -> Dictionary:
    if room_id.strip_edges().is_empty():
        return _failure("Room id must not be empty")
    if not _is_valid_id(room_id):
        return _failure("Room id may only contain letters, digits and underscores: %s" % room_id)
    if not _is_scene_path(path):
        return _failure("Room source path must be a .tscn file: %s" % path)
    if FileAccess.file_exists(path):
        return _failure("Room source already exists: %s" % path)
    if template_path.strip_edges().is_empty() or not FileAccess.file_exists(template_path):
        return _failure("Room template scene is missing: %s" % template_path)
    if not _is_scene_path(template_path):
        return _failure("Room template path must be a .tscn file: %s" % template_path)

    var room_name := "Room_%s" % room_id
    var shown_name := display_name.strip_edges()
    if shown_name.is_empty():
        shown_name = room_id
    var text := "\n".join([
        "[gd_scene load_steps=2 format=3]",
        "",
        "[ext_resource type=\"PackedScene\" path=\"%s\" id=\"1_template\"]" % template_path,
        "",
        "[node name=\"%s\" instance=ExtResource(\"1_template\")]" % room_name,
        "room_id = \"%s\"" % _escape(room_id),
        "display_name = \"%s\"" % _escape(shown_name),
        "",
    ])
    var file := FileAccess.open(path, FileAccess.WRITE)
    if file == null:
        return _failure("Could not write room source: %s" % path)
    file.store_string(text)
    file.close()
    return {"ok": true, "errors": [], "warnings": [], "path": path}


static func write_new_room(
    path: String,
    room_id: String,
    display_name: String = "",
    template_path: String = ""
) -> Dictionary:
    var template := template_path
    if template.is_empty():
        template = String(ProjectSettings.get_setting(TEMPLATE_SETTING, ""))
    return write_inherited_scene(path, template, room_id, display_name)


static func _is_valid_id(room_id: String) -> bool:
    if room_id.is_empty():
        return false
    for index in room_id.length():
        var code := room_id.unicode_at(index)
        var is_lower := code >= 97 and code <= 122
        var is_upper := code >= 65 and code <= 90
        var is_digit := code >= 48 and code <= 57
        if not (is_lower or is_upper or is_digit or code == 95):
            return false
    return true


static func _is_scene_path(path: String) -> bool:
    return path.ends_with(".tscn") and (path.begins_with("res://") or path.begins_with("user://"))


static func _escape(value: String) -> String:
    return value.replace("\\", "\\\\").replace("\"", "\\\"")


static func _failure(message: String) -> Dictionary:
    return {"ok": false, "errors": [message], "warnings": []}
