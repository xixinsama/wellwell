extends RefCounted


func configure(_definition: Resource) -> void:
	pass


func activate() -> bool:
	return true


func cancel() -> bool:
	return true


func tick() -> void:
	pass
