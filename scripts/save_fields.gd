extends RefCounted


# Only explicitly listed gameplay fields are persisted. Never serialize nodes/resources.
static func capture(owner: Object, fields: PackedStringArray) -> Dictionary:
	var data: Dictionary = {}
	for field: String in fields:
		data[field] = owner.get(field)
	return data.duplicate(true)


static func restore(owner: Object, data: Dictionary, fields: PackedStringArray) -> void:
	for field: String in fields:
		owner.set(field, data[field])


static func matches(owner: Object, data: Dictionary, fields: PackedStringArray) -> bool:
	for field: String in fields:
		if not data.has(field) or typeof(data[field]) != typeof(owner.get(field)):
			return false
		if data[field] is float and not is_finite(data[field]):
			return false
	return true
