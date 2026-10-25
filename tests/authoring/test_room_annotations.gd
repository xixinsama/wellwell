extends Node

## Coverage for the World editor room annotation service: entity discovery,
## transform accumulation, ids, caching and missing scenes.

const ANNOTATIONS := preload("res://addons/world_editor/authoring/world/room_annotation_service.gd")
const ROOM_DATA := preload("res://addons/platformer_kit/world/data/room_data.gd")
const SPAWN := preload("res://addons/platformer_kit/world/entities/spawn_point.gd")
const ENTRANCE := preload("res://addons/platformer_kit/world/entities/room_entrance.gd")
const SAVE := preload("res://addons/platformer_kit/world/entities/save_point.gd")
const CUSTOM := preload("res://addons/platformer_kit/world/entities/world_entity.gd")
const SCENE := "user://world_annotations.tscn"


func run() -> Array[String]:
	var failures: Array[String] = []
	_build_scene()
	_assert_collects_anchors(failures)
	_assert_cache_hits(failures)
	_assert_missing_scene(failures)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SCENE))
	return failures


func _assert_collects_anchors(failures: Array[String]) -> void:
	var service := ANNOTATIONS.new() as RoomAnnotationService
	var annotations := service.collect(_make_room())
	if annotations.size() != 4:
		failures.append("expected 4 annotations, got %d" % annotations.size())
		return
	_assert_annotation(annotations, RoomAnnotationService.TYPE_SPAWN, "start", Vector2(20, 12), failures)
	_assert_annotation(annotations, RoomAnnotationService.TYPE_ENTRANCE, "east", Vector2(52, 12), failures)
	_assert_annotation(annotations, RoomAnnotationService.TYPE_SAVE, "save_a", Vector2(28, 28), failures)
	_assert_annotation(annotations, RoomAnnotationService.TYPE_WORLD_ENTITY, "custom", Vector2(12, 36), failures)


func _assert_annotation(
	annotations: Array[Dictionary],
	type: StringName,
	id: String,
	position: Vector2,
	failures: Array[String]
) -> void:
	for annotation: Dictionary in annotations:
		if annotation["type"] == type and annotation["id"] == id:
			if not (annotation["position"] as Vector2).is_equal_approx(position):
				failures.append("%s %s position was %s, expected %s" % [type, id, annotation["position"], position])
			return
	failures.append("missing annotation %s %s" % [type, id])


func _assert_cache_hits(failures: Array[String]) -> void:
	var service := ANNOTATIONS.new() as RoomAnnotationService
	var calls := [0]
	service.load_provider = func(path: String) -> PackedScene:
		calls[0] += 1
		return ResourceLoader.load(path, "PackedScene") as PackedScene
	var room := _make_room()
	service.collect(room)
	service.collect(room)
	if int(calls[0]) != 1:
		failures.append("runtime scene was loaded %d times for an unchanged file" % int(calls[0]))


func _assert_missing_scene(failures: Array[String]) -> void:
	var service := ANNOTATIONS.new() as RoomAnnotationService
	var room := _make_room()
	room.scene_path = "user://world_annotations_missing.tscn"
	if not service.collect(room).is_empty():
		failures.append("missing runtime scene returned annotations")


func _make_room() -> RoomData:
	var room := ROOM_DATA.new() as RoomData
	room.room_id = "annotations_test"
	room.scene_path = SCENE
	return room


func _build_scene() -> void:
	var root := Node2D.new()
	root.name = "Runtime"
	var entities := Node2D.new()
	entities.name = "Entities"
	entities.position = Vector2(4, 4)
	root.add_child(entities)

	var spawn := SPAWN.new() as SpawnPoint
	spawn.name = "Spawn"
	spawn.spawn_id = "start"
	spawn.position = Vector2(16, 8)
	entities.add_child(spawn)

	var entrance := ENTRANCE.new() as RoomEntrance
	entrance.name = "Door"
	entrance.entity_id = "east"
	entrance.position = Vector2(48, 8)
	entities.add_child(entrance)

	var save := SAVE.new() as SavePoint
	save.name = "Save"
	save.entity_id = "save_a"
	save.position = Vector2(24, 24)
	entities.add_child(save)

	var custom := CUSTOM.new() as WorldEntity
	custom.name = "Custom"
	custom.entity_id = "custom"
	custom.position = Vector2(8, 32)
	entities.add_child(custom)

	entities.owner = root
	for child: Node in entities.get_children():
		child.owner = root

	var packed := PackedScene.new()
	packed.pack(root)
	ResourceSaver.save(packed, SCENE)
	root.free()
