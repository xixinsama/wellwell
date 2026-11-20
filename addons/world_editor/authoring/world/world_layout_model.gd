@tool
class_name WorldLayoutModel
extends RefCounted

const ROOM_DATA_SCRIPT: Script = preload("res://addons/platformer_kit/world/data/room_data.gd")
const ROOM_CONNECTION_DATA_SCRIPT: Script = preload("res://addons/platformer_kit/world/data/room_connection_data.gd")
const ROOM_PLACEMENT_DATA_SCRIPT: Script = preload("res://addons/platformer_kit/world/data/world_room_placement_data.gd")
const WORLD_VALIDATION: Script = preload("res://addons/platformer_kit/world/data/world_validation.gd")

## "Pick a chunk for me" marker used by the room importer's optional origin.
## A signed 64-bit style sentinel so any real chunk is still expressible.
const AUTO_ORIGIN := Vector2i(-2147483648, -2147483648)
## Upper bound for the free-chunk search; a world this wide is already unusable.
const FREE_ORIGIN_SEARCH_LIMIT := 512


func add_room(world: WorldData, room: RoomData, origin_chunk: Vector2i = Vector2i.ZERO) -> Dictionary:
    if world == null:
        return _error("world is null")
    if room == null:
        return _error("room is null")
    if room.room_id.is_empty():
        return _error("room has empty room_id")
    if world.has_room(room.room_id):
        return _error("duplicate room_id: %s" % room.room_id)
    world.rooms.append(room)
    if not world.set_room_origin_chunk(room.room_id, origin_chunk):
        world.rooms.erase(room)
        return _error("could not create placement for room: %s" % room.room_id)
    world.sort_for_serialization()
    return _success()


func remove_room(world: WorldData, room_id: String) -> Dictionary:
    if world == null:
        return _error("world is null")
    if not world.has_room(room_id):
        return _error("room_id does not reference a room: %s" % room_id)
    for index: int in range(world.rooms.size() - 1, -1, -1):
        var room: Resource = world.rooms[index]
        if _is_room_data(room) and room.room_id == room_id:
            world.rooms.remove_at(index)
    for index: int in range(world.placements.size() - 1, -1, -1):
        var placement: Resource = world.placements[index]
        if _is_room_placement_data(placement) and placement.room_id == room_id:
            world.placements.remove_at(index)
    for index: int in range(world.connections.size() - 1, -1, -1):
        var connection: Resource = world.connections[index]
        if not _is_room_connection_data(connection):
            continue
        if connection.from_room_id == room_id or connection.to_room_id == room_id:
            world.connections.remove_at(index)
    if world.start_room_id == room_id:
        world.start_room_id = ""
        world.start_spawn_id = ""
    world.sort_for_serialization()
    return _success()


func move_room(world: WorldData, room_id: String, origin_chunk: Vector2i) -> Dictionary:
    if world == null:
        return _error("world is null")
    var room: Resource = world.get_room(room_id)
    if room == null:
        return _error("room_id does not reference a room: %s" % room_id)
    if not world.set_room_origin_chunk(room_id, origin_chunk):
        return _error("could not update placement for room: %s" % room_id)
    return _success()


## Returns [param desired] when a room of [param room_size_chunks] fits there
## without touching another room, otherwise the nearest free chunk.
##
## Search order is deterministic: rings of growing Chebyshev distance around
## [param desired], each ring scanned by (y, x). The result never overlaps an
## existing room, so imported rooms land side by side instead of on top of each
## other.
func find_free_origin_chunk(world: WorldData, desired: Vector2i, room_size_chunks: Vector2i) -> Vector2i:
    var size := _sanitized_room_size(room_size_chunks)
    if _origin_is_free(world, desired, size):
        return desired
    for distance: int in range(1, FREE_ORIGIN_SEARCH_LIMIT + 1):
        for candidate: Vector2i in _chebyshev_ring(desired, distance):
            if _origin_is_free(world, candidate, size):
                return candidate
    return desired


## First free chunk scanning row-major from (0, 0): an empty world yields
## (0, 0), and a world already holding (0, 0) yields the next free chunk on that
## row rather than a chunk above/left of the origin.
func find_default_origin_chunk(world: WorldData, room_size_chunks: Vector2i) -> Vector2i:
    var size := _sanitized_room_size(room_size_chunks)
    for y: int in range(0, FREE_ORIGIN_SEARCH_LIMIT + 1):
        for x: int in range(0, FREE_ORIGIN_SEARCH_LIMIT + 1):
            var candidate := Vector2i(x, y)
            if _origin_is_free(world, candidate, size):
                return candidate
    return Vector2i.ZERO


func connect_rooms(world: WorldData, connection: RoomConnectionData) -> Dictionary:
    if world == null:
        return _error("world is null")
    if connection == null:
        return _error("connection is null")
    if connection.from_room_id.is_empty() or connection.from_entrance_id.is_empty():
        return _error("connection source endpoint is incomplete")
    if connection.to_room_id.is_empty() or connection.to_spawn_id.is_empty():
        return _error("connection target endpoint is incomplete")
    if world.get_connection(connection.from_room_id, connection.from_entrance_id) != null:
        return _error(
            "duplicate connection source endpoint: %s:%s"
            % [connection.from_room_id, connection.from_entrance_id]
        )
    var source_room: Resource = world.get_room(connection.from_room_id)
    var target_room: Resource = world.get_room(connection.to_room_id)
    if source_room == null:
        return _error("connection references unknown from_room_id: %s" % connection.from_room_id)
    if target_room == null:
        return _error("connection references unknown to_room_id: %s" % connection.to_room_id)
    if not source_room.entrance_ids.has(connection.from_entrance_id):
        return _error("connection references unknown source entrance: %s" % connection.from_entrance_id)
    if not target_room.spawn_ids.has(connection.to_spawn_id):
        return _error("connection references unknown target spawn: %s" % connection.to_spawn_id)
    world.connections.append(connection)
    world.sort_for_serialization()
    return _success()


func disconnect_rooms(world: WorldData, from_room_id: String, from_entrance_id: String) -> Dictionary:
    if world == null:
        return _error("world is null")
    for index: int in range(world.connections.size()):
        var connection: Resource = world.connections[index]
        if not _is_room_connection_data(connection):
            continue
        if connection.from_room_id == from_room_id and connection.from_entrance_id == from_entrance_id:
            world.connections.remove_at(index)
            world.sort_for_serialization()
            return _success()
    return _error("connection source endpoint does not exist: %s:%s" % [from_room_id, from_entrance_id])


func validate_world(world: WorldData) -> Dictionary:
    return WORLD_VALIDATION.validate_world_report(world)


func capture_world_state(world: WorldData) -> Dictionary:
    if world == null:
        return {}
    return {
        "rooms": world.rooms.duplicate(),
        "placements": _duplicate_resources(world.placements),
        "connections": world.connections.duplicate(),
        "start_room_id": world.start_room_id,
        "start_spawn_id": world.start_spawn_id,
    }


func restore_world_state(world: WorldData, state: Dictionary) -> Dictionary:
    if world == null:
        return _error("world is null")
    if not state.has("rooms") or not state.has("connections"):
        return _error("world state is incomplete")
    world.rooms.assign(state["rooms"])
    world.placements.assign(_duplicate_resources(state.get("placements", [])))
    world.connections.assign(state["connections"])
    world.start_room_id = String(state.get("start_room_id", ""))
    world.start_spawn_id = String(state.get("start_spawn_id", ""))
    world.sort_for_serialization()
    return _success()


func replace_room(world: WorldData, room_id: String, replacement: RoomData) -> Dictionary:
    if world == null:
        return _error("world is null")
    var current: Resource = world.get_room(room_id)
    if current == null:
        return _error("room_id does not reference a room: %s" % room_id)
    if replacement == null or replacement.room_id != room_id:
        return _error("replacement room_id does not match: %s" % room_id)
    for index: int in range(world.rooms.size()):
        if world.rooms[index] == current:
            world.rooms[index] = replacement
            world.sort_for_serialization()
            return _success()
    return _error("room reference could not be replaced: %s" % room_id)


func _success() -> Dictionary:
    return {"ok": true, "errors": [], "warnings": []}


func _success_with_warnings(values: Variant) -> Dictionary:
    var warnings: Array[String] = []
    for value: Variant in values:
        warnings.append(String(value))
    return {"ok": true, "errors": [], "warnings": warnings}


func _error(message: String) -> Dictionary:
    return {"ok": false, "errors": [message], "warnings": []}


func _from_world_result(result: Dictionary) -> Dictionary:
    return {
        "ok": false,
        "errors": result.get("errors", []),
        "warnings": result.get("warnings", []),
    }


func _duplicate_resources(values: Variant) -> Array[Resource]:
    var result: Array[Resource] = []
    for value: Variant in values:
        if value is Resource:
            result.append((value as Resource).duplicate(true))
    return result


func _sanitized_room_size(room_size_chunks: Vector2i) -> Vector2i:
    return Vector2i(maxi(1, room_size_chunks.x), maxi(1, room_size_chunks.y))


func _origin_is_free(world: WorldData, origin: Vector2i, room_size_chunks: Vector2i) -> bool:
    if world == null:
        return true
    var candidate := Rect2i(origin, room_size_chunks)
    for room_id: String in world.get_room_ids():
        if candidate.intersects(world.get_room_chunk_rect(room_id)):
            return false
    return true


func _chebyshev_ring(center: Vector2i, distance: int) -> Array[Vector2i]:
    var ring: Array[Vector2i] = []
    for dy: int in range(-distance, distance + 1):
        for dx: int in range(-distance, distance + 1):
            if maxi(absi(dx), absi(dy)) != distance:
                continue
            ring.append(center + Vector2i(dx, dy))
    ring.sort_custom(func(left: Vector2i, right: Vector2i) -> bool:
        if left.y != right.y:
            return left.y < right.y
        return left.x < right.x
    )
    return ring


static func _is_room_data(resource: Resource) -> bool:
    return resource != null and resource.get_script() == ROOM_DATA_SCRIPT


static func _is_room_connection_data(resource: Resource) -> bool:
    return resource != null and resource.get_script() == ROOM_CONNECTION_DATA_SCRIPT


static func _is_room_placement_data(resource: Resource) -> bool:
    return resource != null and resource.get_script() == ROOM_PLACEMENT_DATA_SCRIPT
