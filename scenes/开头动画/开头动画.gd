extends Control

@export var main_menu: PackedScene
@export var animation_player: AnimationPlayer


func _ready() -> void:
	assert(main_menu != null)
	assert(animation_player != null)
	RenderingServer.set_default_clear_color(Color.BLACK)
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)
	animation_player.animation_finished.connect(_on_animation_finished)
	animation_player.play(&"开头")
	animation_player.advance(0.0)


func _on_animation_finished(_animation_name: StringName) -> void:
	_enter_main_menu.call_deferred()


func _enter_main_menu() -> void:
	var result: Error = get_tree().change_scene_to_packed(main_menu)
	if result != OK:
		push_error("无法进入主菜单：%d" % result)
