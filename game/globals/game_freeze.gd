extends Node

## Global hit-stop used by dash starts (and later by combat). Gameplay is
## paused; HUD, audio and this node keep processing so the timer can expire.
## Jump and dash edges are buffered while frozen, which is what makes an
## instant super/hyper input survive the freeze.

const BUFFERED_ACTIONS: Array[StringName] = [&"jump", &"dash"]

var _remaining := 0.0
var _owns_pause := false
var _buffered: Dictionary[StringName, bool] = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func freeze(seconds: float) -> void:
	if seconds <= 0.0:
		return
	_remaining = maxf(_remaining, seconds)
	if not get_tree().paused:
		_owns_pause = true
		get_tree().paused = true


func is_frozen() -> bool:
	return _remaining > 0.0


func get_remaining() -> float:
	return _remaining


func consume_buffered(action: StringName) -> bool:
	if not _buffered.get(action, false):
		return false
	_buffered[action] = false
	return true


## Releases a freeze owned by this node. Menus keep their own pause.
func release() -> void:
	_remaining = 0.0
	_buffered.clear()
	if _owns_pause:
		_owns_pause = false
		if get_tree().paused:
			get_tree().paused = false


func _process(delta: float) -> void:
	if _remaining <= 0.0:
		return
	for action: StringName in BUFFERED_ACTIONS:
		if Input.is_action_just_pressed(action):
			_buffered[action] = true
	_remaining = maxf(_remaining - maxf(delta, 0.0), 0.0)
	if _remaining > 0.0 or not _owns_pause:
		return
	_owns_pause = false
	if get_tree().paused:
		get_tree().paused = false
