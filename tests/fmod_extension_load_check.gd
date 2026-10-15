extends Node


func _ready() -> void:
	# A missing native extension fails parsing these types before this check can run.
	var bus: FmodBus = FmodServer.get_bus("bus:/")
	var description: FmodEventDescription = FmodServer.get_event("event:/Mx/Mx_MainMenu")
	assert(GameAudio.banks_loaded, "FMOD banks must load at startup.")
	assert(bus != null and bus.is_valid(), "FMOD master bus must be available.")
	assert(description != null and description.is_valid(), "FMOD menu event must be available.")
	var event: FmodEvent = FmodServer.create_event_instance("event:/Mx/Mx_MainMenu")
	assert(event != null and event.is_valid(), "FMOD must create native event instances.")
	event.release()
	print("PASS: FMOD extension types, banks, master bus and native event creation.")
	get_tree().quit()
