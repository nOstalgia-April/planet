extends Node

const Demo = preload("res://scripts/disk_demo.gd")
const Backdrop = preload("res://scripts/ui/technology_backdrop.gd")
const Page = preload("res://scripts/ui/technology_page.gd")
const SHADERS: Array[Shader] = [
	preload("res://features/technology_screen_studies/shaders/01_cabin_phosphor.gdshader"),
	preload("res://features/technology_screen_studies/shaders/02_pigment_flow.gdshader"),
	preload("res://features/technology_screen_studies/shaders/03_gel_membrane.gdshader"),
	preload("res://features/technology_screen_studies/shaders/04_color_echo.gdshader"),
	preload("res://shaders/technology_waves.gdshader")
]
const STUDY_NAMES: PackedStringArray = ["1  舱内显像", "2  色素输送", "3  胶膜感应", "4  取色余波", "0  当前版本"]

@export_enum("舱内显像", "色素输送", "胶膜感应", "取色余波", "当前版本") var study: int = 0

@onready var game: Demo = $Game
@onready var selector: OptionButton = $PreviewControls/Selector
@onready var backdrop: Backdrop = $Game/HUD/Interface/Technology/Background


func _ready() -> void:
	selector.theme = game._layout._technology.theme
	for index in range(STUDY_NAMES.size()):
		selector.add_item(STUDY_NAMES[index])
	selector.item_selected.connect(select_study)
	game.run.candy = 400
	game.run.economy_changed.emit()
	game._layout._show_technology()
	select_study(study)
	if "--capture" in OS.get_cmdline_user_args():
		_capture_studies.call_deferred()
	elif "--movie" in OS.get_cmdline_user_args():
		_record_studies.call_deferred()


func select_study(index: int) -> void:
	study = index
	selector.select(index)
	var screen: ShaderMaterial = backdrop.material as ShaderMaterial
	screen.shader = SHADERS[index]
	if index < 4:
		screen.set_shader_parameter("effect_time", -1.0)
	screen.set_shader_parameter("cursor_activity", 0.0)


func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.is_pressed() or event.is_echo():
		return
	var key: InputEventKey = event as InputEventKey
	if key.keycode >= KEY_1 and key.keycode <= KEY_4:
		select_study(key.keycode - KEY_1)
	elif key.keycode == KEY_0:
		select_study(4)
	else:
		return
	get_viewport().set_input_as_handled()


func _capture_studies() -> void:
	$PreviewControls.hide()
	backdrop.set_process(false)
	backdrop.set_process_input(false)
	var screen: ShaderMaterial = backdrop.material as ShaderMaterial
	for resolution in [Vector2i(1280, 800), Vector2i(1920, 1080)]:
		get_window().size = resolution
		await get_tree().create_timer(0.3).timeout
		var page: Page = game._layout._technology
		var baseline_positions: Array[Vector2] = []
		for node_value in page._nodes.values():
			var node: Control = node_value as Control
			baseline_positions.append(node.global_position)
		var baseline_links: Array[Vector2i] = page.graph.links.duplicate()
		for index in range(4):
			select_study(index)
			screen.set_shader_parameter("effect_time", 1.6)
			screen.set_shader_parameter("cursor_activity", 0.0)
			await _save("study_%d_%dx%d" % [index + 1, resolution.x, resolution.y])
			var node_index: int = 0
			for node_value in page._nodes.values():
				var node: Control = node_value as Control
				assert(node.global_position == baseline_positions[node_index])
				node_index += 1
			assert(page.graph.links == baseline_links)
			if resolution.x == 1920:
				screen.set_shader_parameter("effect_time", 4.0)
				screen.set_shader_parameter("cursor_uv", Vector2(0.46, 0.42))
				screen.set_shader_parameter("cursor_activity", 1.0)
				await _save("study_%d_pointer" % [index + 1])
	print("PASS: four background studies rendered; node positions and connections unchanged.")
	get_tree().quit()


func _save(label: String) -> void:
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var result: Error = get_viewport().get_texture().get_image().save_png(
		"res://artifacts/technology_" + label + ".png"
	)
	assert(result == OK)


func _record_studies() -> void:
	backdrop.set_process(false)
	backdrop.set_process_input(false)
	var screen: ShaderMaterial = backdrop.material as ShaderMaterial
	for index in range(4):
		select_study(index)
		for frame in range(120):
			var seconds: float = frame / 24.0
			screen.set_shader_parameter("effect_time", seconds + 1.6)
			screen.set_shader_parameter(
				"cursor_uv", Vector2(0.25 + minf(seconds, 3.0) * 0.12, 0.44)
			)
			var activity: float = clampf(seconds * 2.0, 0.0, 1.0) * clampf(4.0 - seconds, 0.0, 1.0)
			screen.set_shader_parameter("cursor_activity", activity)
			await get_tree().process_frame
			await RenderingServer.frame_post_draw
	print("PASS: four animated studies recorded with the same pointer sweep.")
	get_tree().quit()
