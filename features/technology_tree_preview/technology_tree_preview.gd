extends Control

const PageScript = preload("res://scripts/ui/technology_page.gd")

@export_enum("开局", "可购买", "成长中", "高阶") var preview_state: int = 2

@onready var run: PrototypeRun = $Run
@onready var page: PageScript = $TechnologyPage


func _ready() -> void:
	$PreviewControls.theme = page.theme
	page.technology_upgrade_requested.connect(_purchase_technology)
	page.nest_technology_upgrade_requested.connect(_purchase_nest_technology)
	page.close_requested.connect(_return_to_menu)
	run.economy_changed.connect(_refresh)
	for index: int in range(4):
		var button: Button = $PreviewControls.get_child(index) as Button
		button.add_theme_stylebox_override("normal", page.theme.get_stylebox("disabled", "Button"))
		button.add_theme_color_override("font_color", Color("b4c5c7"))
		button.pressed.connect(set_preview.bind(index))
	resized.connect(_layout)
	set_preview(preview_state)
	_layout()


func set_preview(state: int) -> void:
	preview_state = state
	run.start_run([Vector2(-160.0, -180.0), Vector2(-40.0, -180.0), Vector2(90.0, -180.0)])
	run.candy = 10000
	if state >= 2:
		run.purchase_technology("pipe")
		run.purchase_technology("net_unlock")
		run.purchase_technology("cultivation")
	if state == 3:
		for _index: int in range(3):
			run.purchase_technology("pipe")
		run.purchase_technology("automation")
		run.purchase_technology("combo_unlock")
		run.purchase_technology("combo_reward")
		run.purchase_technology("combo_interval")
		for _index: int in range(2):
			run.purchase_technology("net_capacity")
		run.purchase_nest_technology(1, "valuable")
	run.candy = [0, 80, 35, 180][state]
	page.selected_nest_id = 1
	page.selected_key = ["pipe", "pipe", "combo_unlock", "automation"][state]
	_refresh()
	for index: int in range(4):
		($PreviewControls.get_child(index) as Button).set_pressed_no_signal(index == state)


func _refresh() -> void:
	page.refresh(run, page.selected_nest_id)


func _purchase_technology(id: String) -> void:
	run.purchase_technology(id)


func _purchase_nest_technology(nest_id: int, id: String) -> void:
	run.purchase_nest_technology(nest_id, id)


func _layout() -> void:
	var factor: float = minf(size.x / 1280.0, size.y / 800.0)
	page.scale = Vector2.ONE * factor
	page.size = size / factor - Vector2(0.0, 48.0)
	$PreviewControls.scale = Vector2.ONE * factor
	$PreviewControls.position = Vector2(24.0 * factor, size.y - 43.0 * factor)


func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_return_to_menu()


func _return_to_menu() -> void:
	get_tree().change_scene_to_file.call_deferred("res://scenes/主菜单/主菜单.tscn")
