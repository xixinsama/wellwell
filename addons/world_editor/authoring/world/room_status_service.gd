class_name RoomStatusService
extends RefCounted

## Read-only bake status for a world room.
##
## Pure logic plus injectable IO, so the World editor can show "fresh / stale /
## error / unknown" and the tests can run without real bake outputs.
##
##   fresh   the source hash matches the saved fingerprint and both artifacts exist
##   stale   the source scene changed after the last bake
##   error   a source/artifact is missing, or the last bake failed this session
##   unknown no source path, no fingerprint yet, or no room selected

const FRESH := &"fresh"
const STALE := &"stale"
const ERROR := &"error"
const UNKNOWN := &"unknown"

## (path) -> sha256 string. Overridable in tests.
var hash_provider: Callable
## (path) -> bool. Overridable in tests.
var exists_provider: Callable

var _hash_cache: Dictionary = {}
var _bake_failures: Dictionary = {}


func _init() -> void:
    hash_provider = _default_hash
    exists_provider = _default_exists


## Evaluate one room. Returns {state: StringName, message: String}.
func evaluate(room: RoomData) -> Dictionary:
    if room == null:
        return _result(UNKNOWN, "No room selected", "WE_STATUS_MSG_NO_ROOM")
    if room.room_id.is_empty():
        return _result(UNKNOWN, "Room has no id", "WE_STATUS_MSG_NO_ID")
    var failure := String(_bake_failures.get(room.room_id, ""))
    if not failure.is_empty():
        return _result(ERROR, failure)
    var source_path := room.source_scene_path
    if source_path.is_empty():
        return _result(UNKNOWN, "Room has no source scene path", "WE_STATUS_MSG_NO_SOURCE")
    if not bool(exists_provider.call(source_path)):
        return _result(ERROR, "Source scene is missing: %s" % source_path, "WE_STATUS_MSG_MISSING_SOURCE", [source_path])
    if room.source_fingerprint.is_empty():
        return _result(UNKNOWN, "No bake fingerprint; re-bake the room", "WE_STATUS_MSG_NO_FINGERPRINT")
    if room.scene_path.is_empty() or not bool(exists_provider.call(room.scene_path)):
        return _result(ERROR, "Runtime scene is missing: %s" % room.scene_path, "WE_STATUS_MSG_MISSING_RUNTIME", [room.scene_path])
    if room.terrain_scene_path.is_empty() or not bool(exists_provider.call(room.terrain_scene_path)):
        return _result(ERROR, "Terrain scene is missing: %s" % room.terrain_scene_path, "WE_STATUS_MSG_MISSING_TERRAIN", [room.terrain_scene_path])
    if _source_hash(source_path) != room.source_fingerprint:
        return _result(STALE, "Source scene changed since the last bake", "WE_STATUS_MSG_STALE")
    return _result(FRESH, "Baked", "WE_STATUS_MSG_FRESH")


## Remember a failed bake/validate for the rest of the session.
func mark_bake_failure(room_id: String, message: String) -> void:
    if room_id.is_empty():
        return
    _bake_failures[room_id] = message if not message.is_empty() else "Bake failed"


func clear_bake_failure(room_id: String) -> void:
    _bake_failures.erase(room_id)


func has_bake_failure(room_id: String) -> bool:
    return _bake_failures.has(room_id)


func clear_cache() -> void:
    _hash_cache.clear()


## Recomputed hash for a source scene, cached by (path, mtime, size).
func _source_hash(path: String) -> String:
    var mtime := int(FileAccess.get_modified_time(path))
    var size := _file_size(path)
    var cached: Dictionary = _hash_cache.get(path, {})
    if not cached.is_empty() \
        and int(cached.get("mtime", -1)) == mtime \
        and int(cached.get("size", -1)) == size:
        return String(cached.get("hash", ""))
    var hash := String(hash_provider.call(path))
    _hash_cache[path] = {"mtime": mtime, "size": size, "hash": hash}
    return hash


func _file_size(path: String) -> int:
    var file := FileAccess.open(path, FileAccess.READ)
    if file == null:
        return -1
    var size := file.get_length()
    file.close()
    return size


static func _default_hash(path: String) -> String:
    return FileAccess.get_sha256(path) if FileAccess.file_exists(path) else ""


static func _default_exists(path: String) -> bool:
    return FileAccess.file_exists(path)


static func _result(
    state: StringName,
    message: String,
    message_key: String = "",
    message_args: Array = []
) -> Dictionary:
    return {
        "state": state,
        "message": message,
        "message_key": message_key,
        "message_args": message_args,
    }
