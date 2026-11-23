extends SceneTree

const Px := preload("res://addons/pixelfx/core/px.gd")
const EFFECT_PATHS := [
	"res://game/player/effects/jump_dust.gd",
	"res://game/player/effects/run_dust.gd",
	"res://game/player/effects/land_dust.gd",
	"res://game/player/effects/respawn_hurt.gd",
]
const TIMES := [0.0, 0.08, 0.16, 0.28, 0.44]
const CELL_SIZE := 40
const SCALE := 6


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var scaled_size := CELL_SIZE * SCALE
	var sheet := Image.create(TIMES.size() * scaled_size, EFFECT_PATHS.size() * scaled_size, false, Image.FORMAT_RGBA8)
	sheet.fill(Color("18202a"))
	for row: int in range(EFFECT_PATHS.size()):
		var script := load(EFFECT_PATHS[row]) as Script
		if script == null:
			push_error("preview effect missing: %s" % EFFECT_PATHS[row])
			quit(1)
			return
		var meta: Dictionary = script.get("meta")
		for column: int in range(TIMES.size()):
			var instance: RefCounted = Px.createFx(script, {"x": float(meta.origin[0]), "y": float(meta.origin[1])})
			instance.update(TIMES[column])
			var frame: RefCounted = Px.createFrame(meta.size[0], meta.size[1])
			instance.draw(frame)
			var rgba: PackedByteArray = Px.composite(frame, PackedByteArray(), null)
			var image := Image.create_from_data(frame.w, frame.h, false, Image.FORMAT_RGBA8, rgba)
			var cell := Image.create(CELL_SIZE, CELL_SIZE, false, Image.FORMAT_RGBA8)
			cell.fill(Color(0, 0, 0, 0))
			var feet := Vector2i(int(CELL_SIZE / 2.0), 26)
			cell.fill_rect(Rect2i(feet.x - 4, feet.y - 8, 8, 8), Color("4bdb9f"))
			cell.blend_rect(image, Rect2i(0, 0, frame.w, frame.h), feet - Vector2i(meta.origin[0], meta.origin[1]))
			cell.resize(scaled_size, scaled_size, Image.INTERPOLATE_NEAREST)
			sheet.blend_rect(cell, Rect2i(0, 0, scaled_size, scaled_size), Vector2i(column * scaled_size, row * scaled_size))
	DirAccess.make_dir_recursive_absolute("res://docs/previews")
	var error := sheet.save_png("res://docs/previews/player-motion-effects.png")
	if error != OK:
		push_error("preview save failed: %s" % error_string(error))
		quit(1)
		return
	quit(0)
