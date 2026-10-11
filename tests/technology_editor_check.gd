extends Node

const EditorScene: PackedScene = preload("res://features/technology_editor/科技树调参.tscn")
const TuningScript = preload("res://features/technology_editor/technology_editor.gd")
const SETTINGS_PATH: String = "res://resources/prototype_settings.tres"
const TEST_PATH: String = "user://technology_editor_check.tres"

var _failures: int = 0


func _ready() -> void:
	_check_editor.call_deferred()


func _check_editor() -> void:
	var original_text: String = FileAccess.get_file_as_string(SETTINGS_PATH)
	var source: PrototypeSettings = load(SETTINGS_PATH) as PrototypeSettings
	_check(ResourceSaver.save(source, TEST_PATH) == OK, "prepare isolated settings")
	var editor: TuningScript = EditorScene.instantiate() as TuningScript
	editor.settings_path = TEST_PATH
	add_child(editor)
	await _settle()
	var cost: SpinBox = editor.find_child("base_value_upgrade_costs_0", true, false) as SpinBox
	var multiplier: SpinBox = editor.find_child("base_value_multipliers_1", true, false) as SpinBox
	cost.value = 137
	multiplier.value = 7
	_check(
		editor.run.get_technology_cost("base_value") == 137, "edited price reaches purchase model"
	)
	_check(source.base_value_upgrade_costs[0] != 137, "unsaved edits do not mutate shared resource")
	editor.run.candy = 136
	_check(not editor.run.purchase_technology("base_value"), "insufficient funds still rejected")
	editor.run.candy = 200
	editor._purchase("base_value")
	_check(editor.run.candy == 63, "purchase deducts edited price")
	_check(editor.run.get_base_value() == source.slime_reward * 7, "purchase applies edited effect")
	_check(not editor.run.purchase_technology("giant"), "prerequisites remain enforced")
	# Simulate another editor saving an unrelated field while this draft is open.
	var latest: PrototypeSettings = ResourceLoader.load(
		TEST_PATH, "", ResourceLoader.CACHE_MODE_IGNORE
	)
	latest.nest_initial_delay_seconds = 91
	_check(ResourceSaver.save(latest, TEST_PATH) == OK, "prepare concurrent unrelated edit")
	_check(editor.save_settings() == OK, "save succeeds")
	var saved: PrototypeSettings = ResourceLoader.load(
		TEST_PATH, "", ResourceLoader.CACHE_MODE_IGNORE
	)
	_check(saved.base_value_upgrade_costs[0] == 137, "price survives disk round trip")
	_check(saved.base_value_multipliers[1] == 7, "effect survives disk round trip")
	_check(saved.nest_initial_delay_seconds == 91, "unrelated file edits survive save")
	var backup: PrototypeSettings = load(
		"user://technology_editor_check.before_technology_save.tres"
	)
	_check(
		backup.base_value_upgrade_costs[0] == source.base_value_upgrade_costs[0],
		"backup contains original price"
	)
	cost.value = 999
	editor.reload_settings()
	_check(editor.settings.base_value_upgrade_costs[0] == 137, "discard restores last saved price")
	_check(editor.run.base_value_level == 0, "reload resets only preview progress")
	_check(
		FileAccess.get_file_as_string(SETTINGS_PATH) == original_text,
		"production settings unchanged by test"
	)
	for index: int in range(editor.GROUPS.size()):
		editor._show_group(index)
		await _settle()
		_check(editor._fields.get_child_count() > 0, "group has controls: " + editor.GROUPS[index])
	var capture: bool = "--capture" in OS.get_cmdline_user_args()
	for dimensions: Vector2i in [Vector2i(1280, 800), Vector2i(1920, 1080)]:
		get_window().size = dimensions
		editor._show_group(0)
		editor._tabs.current_tab = 0
		await _settle()
		_check_layout(editor)
		if capture:
			await _capture("form", dimensions)
		editor._tabs.current_tab = 1
		await _settle()
		_check_layout(editor)
		_check(
			editor.page.purchase.get_global_rect().end.y < editor._save.global_position.y,
			"preview fits above footer"
		)
		if capture:
			await _capture("preview", dimensions)
	editor.queue_free()
	await _settle()
	print("Technology editor check: %d failures" % _failures)
	get_tree().quit(1 if _failures > 0 else 0)


func _check_layout(editor: TuningScript) -> void:
	var screen: Rect2 = get_viewport().get_visible_rect()
	for control: Control in [editor._save, editor._status, editor._tabs]:
		_check(screen.encloses(control.get_global_rect()), "editor control stays on screen")


func _settle() -> void:
	for frame: int in range(5):
		await get_tree().process_frame


func _capture(label: String, dimensions: Vector2i) -> void:
	await RenderingServer.frame_post_draw
	var path: String = (
		"res://artifacts/technology_editor_%s_%dx%d.png" % [label, dimensions.x, dimensions.y]
	)
	_check(get_viewport().get_texture().get_image().save_png(path) == OK, "save screenshot")


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)
