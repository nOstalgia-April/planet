class_name PlanetWebFmod
extends RefCounted
## Typed HTML5 handles used only by the staged web export.
## Desktop scripts keep the native FMOD types; tools/build_web.ps1 selects this adapter.


class Event:
	extends RefCounted
	var handle: JavaScriptObject

	func _init(value: JavaScriptObject) -> void:
		handle = value

	func is_valid() -> bool:
		return handle.is_valid()

	func start() -> void:
		handle.start()

	func stop(mode: int) -> void:
		handle.stop(mode)

	func release() -> void:
		handle.release()

	func set_volume(value: float) -> void:
		handle.set_volume(value)

	func set_paused(value: bool) -> void:
		handle.set_paused(value)

	func set_parameter_by_name(parameter: String, value: float) -> void:
		handle.set_parameter_by_name(parameter, value)

	func get_timeline_position() -> int:
		return int(handle.get_timeline_position())

	func get_playback_state() -> int:
		return int(handle.get_playback_state())


class Parameter:
	extends RefCounted
	var data: Dictionary

	func _init(value: Dictionary) -> void:
		data = value

	func get_name() -> String:
		return data["name"]

	func get_minimum() -> float:
		return data["minimum"]

	func get_maximum() -> float:
		return data["maximum"]


class Description:
	extends RefCounted
	var handle: JavaScriptObject

	func _init(value: JavaScriptObject) -> void:
		handle = value

	func get_path() -> String:
		return handle.get_path()

	func get_length() -> int:
		return int(handle.get_length())

	func get_instance_count() -> int:
		return int(handle.get_instance_count())

	func get_instance_list() -> Array[Event]:
		var result: Array[Event] = []
		var values: JavaScriptObject = handle.get_instance_list()
		for index: int in range(int(values.length)):
			result.append(Event.new(values[str(index)]))
		return result

	func get_parameter_count() -> int:
		return int(handle.get_parameter_count())

	func get_parameter_by_index(index: int) -> Parameter:
		var data: Dictionary = JSON.parse_string(handle.get_parameter_json(index))
		return Parameter.new(data)


class Bank:
	extends RefCounted
	var handle: JavaScriptObject

	func _init(value: JavaScriptObject) -> void:
		handle = value

	func get_description_list() -> Array[Description]:
		var result: Array[Description] = []
		var values: JavaScriptObject = handle.get_description_list()
		for index: int in range(int(values.length)):
			result.append(Description.new(values[str(index)]))
		return result


class Bus:
	extends RefCounted
	var handle: JavaScriptObject

	func _init(value: JavaScriptObject) -> void:
		handle = value

	func set_mute(value: bool) -> void:
		handle.set_mute(value)
