class_name PlatformerDebugOverlay2D
extends Node2D

## Optional runtime debug overlay for a gameplay subject.
##
## Binds the subject (the player by default) to the debug visualizer and, when
## [member hud_path] is configured, to the debug HUD text panel. Press
## [member toggle_keycode] (F3 by default) to hide or show everything at once.
##
## The overlay is a Node2D so it stays inside the world viewport and draws the
## vectors in world space. The HUD lives in a CanvasLayer and is referenced by
## path, which keeps pixel sizes consistent with the rest of the HUD.

signal enabled_changed(enabled: bool)

@export var subject_path := NodePath("../Player")
@export var hud_path := NodePath()
@export var visualizer_path := NodePath("Visualizer")
@export var toggle_keycode: Key = KEY_F3
@export var start_enabled := true
@export var hide_hud_when_disabled := true

var _subject: Node
var _visualizer: Node2D
var _hud: Control
var _enabled := true
var _toggle_was_pressed := false


func _ready() -> void:
	_enabled = start_enabled
	_resolve_nodes()
	_bind_nodes()
	_apply_state()


func _process(_delta: float) -> void:
	if _subject == null:
		_resolve_nodes()
		_bind_nodes()
	_poll_toggle()
	_apply_state()


func set_enabled(value: bool) -> void:
	value = bool(value)
	if value == _enabled:
		_apply_state()
		return
	_enabled = value
	_apply_state()
	enabled_changed.emit(_enabled)


func is_enabled() -> bool:
	return _enabled


func bind_subject(subject: Node) -> void:
	_subject = subject
	_resolve_nodes()
	_bind_nodes()
	_apply_state()


func get_subject() -> Node:
	return _subject


func get_hud() -> Control:
	return _hud


func _resolve_nodes() -> void:
	if _visualizer == null:
		_visualizer = get_node_or_null(visualizer_path) as Node2D
	if _hud == null and hud_path != NodePath():
		_hud = get_node_or_null(hud_path) as Control
	if _subject == null:
		_subject = get_node_or_null(subject_path)


func _bind_nodes() -> void:
	if _subject == null:
		return
	if _visualizer != null and _visualizer.has_method("bind_subject"):
		_visualizer.call("bind_subject", _subject)
	if _hud == null:
		return
	if _hud.has_method("bind_player"):
		_hud.call("bind_player", _subject)
	elif _hud.has_method("bind_subject"):
		_hud.call("bind_subject", _subject)


func _apply_state() -> void:
	visible = _enabled
	if _visualizer != null:
		_visualizer.visible = _enabled
	if _hud != null and hide_hud_when_disabled:
		_hud.visible = _enabled


func _poll_toggle() -> void:
	if toggle_keycode == KEY_NONE:
		return
	var pressed := Input.is_key_pressed(toggle_keycode)
	if pressed and not _toggle_was_pressed:
		set_enabled(not _enabled)
	_toggle_was_pressed = pressed
