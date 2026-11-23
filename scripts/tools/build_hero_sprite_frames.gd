extends SceneTree

const OUTPUT := "res://resources/player/hero_sprite_frames.tres"
const ROWS := [
	["idle", 0, 2, 2.0, true], ["walk", 1, 4, 8.0, true],
	["run", 2, 4, 12.0, true], ["jump", 3, 2, 10.0, false],
	["fall", 4, 2, 6.0, true], ["climb", 5, 2, 8.0, true],
	["look_up", 6, 1, 1.0, false], ["look_down", 7, 1, 1.0, false],
	["look_left", 8, 1, 1.0, false], ["look_right", 9, 1, 1.0, false],
]


func _init() -> void:
	var image := load("res://assets/generated/hero.png") as Texture2D
	if image == null or image.get_size() != Vector2(80, 100):
		push_error("hero.png must be an 80x100 texture")
		quit(1)
		return
	var frames := SpriteFrames.new()
	frames.remove_animation("default")
	for row: Array in ROWS:
		var animation := StringName(row[0])
		frames.add_animation(animation)
		frames.set_animation_speed(animation, row[3])
		frames.set_animation_loop(animation, row[4])
		for column: int in range(row[2]):
			var frame := AtlasTexture.new()
			frame.atlas = image
			frame.region = Rect2(column * 10, row[1] * 10, 10, 10)
			frames.add_frame(animation, frame)
	var error := ResourceSaver.save(frames, OUTPUT)
	if error != OK:
		push_error("could not save Hero SpriteFrames: %s" % error_string(error))
	quit(0 if error == OK else 1)
