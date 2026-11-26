extends RefCounted
## Ownership guard for the shared autopilot simulator.
##
## A room raster, one [AutopilotMotion] and one [AutopilotPlanner] are shared
## between the debug tool, its worker thread, and any playtest or editor probe
## that reaches for them. [method AutopilotGrid.move_box] keeps its result in
## fields on the grid, so two owners simulating at the same time silently corrupt
## each other and produce nonsense routes.
##
## This guard makes the sharing explicit: whoever simulates holds the lock, and a
## second owner gets `false` instead of garbage. Acquisition is reentrant per
## owner, so a planner can call the simulator while holding the lock itself.

var _mutex := Mutex.new()
var _holder: StringName = &""
var _depth := 0


## Take the lock for [param owner]. Returns false when another owner holds it.
func try_acquire(owner: StringName) -> bool:
	if owner.is_empty():
		return false
	_mutex.lock()
	var granted := _holder.is_empty() or _holder == owner
	if granted:
		_holder = owner
		_depth += 1
	_mutex.unlock()
	return granted


## Release one acquisition. Releasing an owner that does not hold it is ignored.
func release(owner: StringName) -> void:
	_mutex.lock()
	if _holder == owner:
		_depth -= 1
		if _depth <= 0:
			_depth = 0
			_holder = &""
	_mutex.unlock()


func is_locked() -> bool:
	_mutex.lock()
	var locked := not _holder.is_empty()
	_mutex.unlock()
	return locked


func holder() -> StringName:
	_mutex.lock()
	var value := _holder
	_mutex.unlock()
	return value


func depth() -> int:
	_mutex.lock()
	var value := _depth
	_mutex.unlock()
	return value
