extends Node

const MENU_SCENE: PackedScene = preload("res://scenes/主菜单/主菜单.tscn")
const Menu = preload("res://scenes/主菜单/主菜单.gd")

var _loader: DelayedSceneLoader = DelayedSceneLoader.new()
var _paths: Array[String] = []
var _failures: int = 0
var _changes: int = 0
var _prefix: String
var _preview_path: String


# A real threaded ResourceLoader request with a controlled delay exercises the
# handoff race without depending on disk speed or loading the entire game.
class DelayedSceneLoader:
	extends ResourceFormatLoader

	func _get_recognized_extensions() -> PackedStringArray:
		return PackedStringArray(["menuloadcheck"])

	func _handles_type(type: StringName) -> bool:
		return type == &"PackedScene"

	func _get_resource_type(_path: String) -> String:
		return "PackedScene"

	func _load(path: String, _original: String, _subthreads: bool, _cache_mode: int) -> Variant:
		OS.delay_msec(350)
		if FileAccess.get_file_as_string(path) == "fail":
			return ERR_FILE_CORRUPT
		var scene: PackedScene = PackedScene.new()
		var node: Node = Node.new()
		node.name = "LoadedFixture"
		var result: Error = scene.pack(node)
		node.free()
		return scene if result == OK else result


func _ready() -> void:
	get_tree().current_scene = null
	get_tree().scene_changed.connect(_on_scene_changed)
	get_tree().create_timer(20.0).timeout.connect(_timed_out)
	_run.call_deferred()


func _run() -> void:
	_prefix = "user://menu_loading_check_%d_" % Time.get_ticks_usec()
	ResourceLoader.add_resource_format_loader(_loader, true)
	_preview_path = _prefix + "preview.tscn"
	var preview: PackedScene = PackedScene.new()
	var node: Node = Node.new()
	node.name = "PreviewFixture"
	assert(preview.pack(node) == OK)
	node.free()
	assert(ResourceSaver.save(preview, _preview_path) == OK)
	_paths.append(_preview_path)
	await _check_early_start()
	await _check_retry()
	await _check_leave_and_return()
	await _check_abandoned_request()
	await _check_shared_handoff()
	ResourceLoader.remove_resource_format_loader(_loader)
	for path: String in _paths:
		DirAccess.remove_absolute(path)
	print(
		(
			"Menu loading: %d failures; early/repeated Start, retry, preview departure/return, shared handoff."
			% _failures
		)
	)
	get_tree().quit(0 if _failures == 0 else 1)


func _check_early_start() -> void:
	var path: String = _fixture("early")
	var menu: Menu = _show_menu(path)
	_check(menu._prepared_scene == null, "Start begins before preparation completes")
	var changes: int = _changes
	menu._start_button.pressed.emit()
	menu._start()
	_check(menu._start_requested and menu._start_button.disabled, "repeated Start stays disabled")
	_check(
		menu._preview_button.disabled and not menu._preview_panel.visible,
		"preview hides while entering"
	)
	_check(not get_tree().root.gui_disable_input, "Start does not lock global GUI input")
	await get_tree().scene_changed
	await get_tree().process_frame
	_check(_changes == changes + 1, "repeated Start changes the scene exactly once")
	_check(get_tree().current_scene.scene_file_path == path, "early Start reaches its scene")
	await _expect_released(path)


func _check_retry() -> void:
	var path: String = _fixture("retry", "fail")
	var menu: Menu = _show_menu(path)
	print("EXPECTED LOAD FAILURE: controlled corrupt fixture; the following retry must recover.")
	menu._start_button.pressed.emit()
	while menu._start_requested:
		await get_tree().process_frame
	_check(get_tree().current_scene == menu, "load failure keeps the menu")
	_check(
		not menu._start_button.disabled and menu._start_button.text == "重试",
		"failure restores Retry"
	)
	_check(not menu._preview_button.disabled, "failure restores preview access")
	await _expect_released(path)
	_write_fixture(path, "ok")
	menu._start_button.pressed.emit()
	await get_tree().scene_changed
	_check(get_tree().current_scene.scene_file_path == path, "Retry reloads the repaired scene")
	await _expect_released(path)


func _check_leave_and_return() -> void:
	var path: String = _fixture("return")
	var menu: Menu = _show_menu(path)
	_check(
		ResourceLoader.load_threaded_get_status(path) == ResourceLoader.THREAD_LOAD_IN_PROGRESS,
		"preview leaves during active loading"
	)
	var started: int = Time.get_ticks_msec()
	menu._open_scene(_preview_path)
	_check(Time.get_ticks_msec() - started < 200, "opening preview does not wait for gameplay load")
	await get_tree().scene_changed
	menu = _show_menu(path)
	menu._start_button.pressed.emit()
	await get_tree().scene_changed
	_check(get_tree().current_scene.scene_file_path == path, "returning menu retains its request")
	await _expect_released(path)


func _check_abandoned_request() -> void:
	var path: String = _fixture("abandoned")
	var menu: Menu = _show_menu(path)
	menu._open_scene(_preview_path)
	await get_tree().scene_changed
	await _expect_released(path)
	_check(
		get_tree().current_scene.scene_file_path == _preview_path,
		"background cleanup keeps the chosen preview"
	)


func _check_shared_handoff() -> void:
	var path: String = _fixture("handoff")
	assert(Menu.prepare_scene(path) == OK)
	Menu.release_scene(get_tree(), path)
	var menu: Menu = _show_menu(path)
	menu._start_button.pressed.emit()
	await get_tree().scene_changed
	_check(
		get_tree().current_scene.scene_file_path == path,
		"intro cleanup cannot consume the menu request"
	)
	await _expect_released(path)


func _show_menu(path: String) -> Menu:
	if get_tree().current_scene != null:
		get_tree().current_scene.free()
	var menu: Menu = MENU_SCENE.instantiate() as Menu
	menu.start_scene = path
	get_tree().root.add_child(menu)
	get_tree().current_scene = menu
	return menu


func _fixture(label: String, content: String = "ok") -> String:
	var path: String = _prefix + label + ".menuloadcheck"
	_write_fixture(path, content)
	_paths.append(path)
	return path


func _write_fixture(path: String, content: String) -> void:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	assert(file != null)
	file.store_string(content)
	file.close()


func _expect_released(path: String) -> void:
	var deadline: int = Time.get_ticks_msec() + 3000
	while (
		ResourceLoader.load_threaded_get_status(path) != ResourceLoader.THREAD_LOAD_INVALID_RESOURCE
		and Time.get_ticks_msec() < deadline
	):
		await get_tree().process_frame
	_check(
		(
			ResourceLoader.load_threaded_get_status(path)
			== ResourceLoader.THREAD_LOAD_INVALID_RESOURCE
		),
		"completed request is fully consumed: " + path.get_file()
	)


func _on_scene_changed() -> void:
	_changes += 1


func _timed_out() -> void:
	push_error("Menu loading check timed out.")
	get_tree().quit(1)


func _check(value: bool, description: String) -> void:
	if not value:
		_failures += 1
		push_error(description)
