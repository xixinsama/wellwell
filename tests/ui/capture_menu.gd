extends SceneTree

const OUTPUT_DIR := "res://.godot/menu_captures"

func _init() -> void:
	call_deferred("_capture_screens")

func _capture_screens() -> void:
	var original_locale := TranslationServer.get_locale()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	change_scene_to_file("res://scenes/main.tscn")
	await process_frame
	await process_frame
	await process_frame
	_save_capture("main_menu.png")

	var menu := root.get_node_or_null("Main/HUD/MainMenu")
	if menu != null:
		menu.call("_open_save_slots")
	await process_frame
	await process_frame
	_save_capture("save_slots.png")

	if menu != null:
		menu.call("_show_home")
		menu.call("_open_settings")
	await process_frame
	await process_frame
	_save_capture("settings.png")

	var settings := root.get_node_or_null("Main/HUD/Settings")
	if settings != null:
		settings.call("_request_back")
	TranslationServer.set_locale("en")
	if menu != null:
		menu.show()
		menu.call("_show_home")
	await process_frame
	await process_frame
	_save_capture("main_menu_en.png")
	if menu != null:
		menu.call("_open_save_slots")
	await process_frame
	await process_frame
	_save_capture("save_slots_en.png")
	if menu != null:
		menu.call("_show_home")
		menu.call("_open_settings")
	await process_frame
	await process_frame
	_save_capture("settings_en.png")
	TranslationServer.set_locale(original_locale)
	quit()

func _save_capture(file_name: String) -> void:
	var image := root.get_texture().get_image()
	image.save_png("%s/%s" % [OUTPUT_DIR, file_name])
