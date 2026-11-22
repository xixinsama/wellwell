@tool
extends Marker2D
class_name SpawnPoint

@export var spawn_id: String:
    get:
        return _spawn_id
    set(value):
        var previous_id := _spawn_id
        _spawn_id = value
        if previous_id != value:
            _notify_room_authoring_root(previous_id)

var _spawn_id := "start"


## A room's preview spawn follows its SpawnPoint when it is renamed, so authors
## never have to keep the root's preview_spawn_id in sync by hand.
func _notify_room_authoring_root(previous_id: String) -> void:
    var node: Node = get_parent()
    while node != null:
        if node.has_method("on_spawn_id_renamed"):
            node.call("on_spawn_id_renamed", previous_id, _spawn_id)
            return
        node = node.get_parent()
