extends Node

const Dialogue = preload("res://scripts/ui/mascot_dialogue.gd")

@onready var dialogue: Dialogue = $DialogueLayer/MascotDialogue
@onready var game: Node = $Game


func _ready() -> void:
	# Keep child artwork animating and responding to window resize, but stop gameplay.
	game.set_process(false)
	game.set_process_input(false)
	game.set_process_unhandled_input(false)


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_R:
				dialogue.play(dialogue.lines)
			KEY_SPACE, KEY_ENTER:
				dialogue.advance()
	# Background buttons and shortcuts must not pause or leave the dialogue preview.
	get_viewport().set_input_as_handled()
