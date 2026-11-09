extends Node
## Installed as FmodServer only in the web build, before GameAudio.

var FMOD_STUDIO_LOAD_BANK_NORMAL: int
var FMOD_STUDIO_STOP_IMMEDIATE: int
var FMOD_STUDIO_STOP_ALLOWFADEOUT: int
var FMOD_STUDIO_PLAYBACK_STOPPED: int
var _bridge: JavaScriptObject


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_bridge = JavaScriptBridge.get_interface("PlanetFmod")
	assert(_bridge != null and _bridge.ready, "The HTML shell must initialize FMOD before Godot.")
	FMOD_STUDIO_LOAD_BANK_NORMAL = int(_bridge.get_constant("STUDIO_LOAD_BANK_NORMAL"))
	FMOD_STUDIO_STOP_IMMEDIATE = int(_bridge.get_constant("STUDIO_STOP_IMMEDIATE"))
	FMOD_STUDIO_STOP_ALLOWFADEOUT = int(_bridge.get_constant("STUDIO_STOP_ALLOWFADEOUT"))
	FMOD_STUDIO_PLAYBACK_STOPPED = int(_bridge.get_constant("STUDIO_PLAYBACK_STOPPED"))


func _process(_delta: float) -> void:
	update()


func update() -> void:
	_bridge.update()


func load_bank(path: String, _flags: int) -> PlanetWebFmod.Bank:
	return PlanetWebFmod.Bank.new(_bridge.load_bank(path))


func check_event_path(path: String) -> bool:
	return _bridge.check_event_path(path)


func check_bus_path(path: String) -> bool:
	return _bridge.check_bus_path(path)


func get_event(path: String) -> PlanetWebFmod.Description:
	return PlanetWebFmod.Description.new(_bridge.get_event(path))


func create_event_instance(path: String) -> PlanetWebFmod.Event:
	return PlanetWebFmod.Event.new(_bridge.create_event_instance(path))


func get_bus(path: String) -> PlanetWebFmod.Bus:
	return PlanetWebFmod.Bus.new(_bridge.get_bus(path))


func get_global_parameter_desc_list() -> Array:
	return JSON.parse_string(_bridge.get_global_parameters_json())


func set_global_parameter_by_name(parameter: String, value: float) -> void:
	_bridge.set_global_parameter_by_name(parameter, value)
