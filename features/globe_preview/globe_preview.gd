extends Control

const GlobeMath = preload("res://features/globe_preview/globe_math.gd")
const MonsterView = preload("res://features/globe_preview/monster_view.gd")
const MONSTER_SCENE: PackedScene = preload("res://features/globe_preview/monster_view.tscn")
const DEFAULT_TEXTURE_PATH: String = "res://assets/globe_preview/monster_cutout.png"
const LANDMARK_POSITION: Vector3 = Vector3(-0.37, 0.13, 1.0)
const OVERVIEW_CAMERA_DISTANCE: float = 3.4

@export var monster_texture: Texture2D
@export_range(12, 120, 1) var monster_count: int = 36
@export_range(40.0, 110.0, 0.1) var monster_height: float = 45.6
@export_range(1.1, 2.0, 0.01) var closest_camera_distance: float = 1.35

var _orientation: Quaternion = Quaternion.IDENTITY
var _zoom: float = 1.0
var _planet_radius: float = 280.0
var _planet_center: Vector2 = Vector2.ZERO
var _overview_radius: float = 280.0
var _camera_distance: float = OVERVIEW_CAMERA_DISTANCE
var _focal_length: float = 280.0
var _monsters: Array[MonsterView] = []
var _display_texture: Texture2D
var _alpha_mask: BitMap
var _dragging: bool = false
var _drag_moved: bool = false
var _drag_start_mouse: Vector2 = Vector2.ZERO
var _drag_start_vector: Vector3 = Vector3.ZERO
var _drag_start_orientation: Quaternion = Quaternion.IDENTITY
var _selected_monster: MonsterView
var _hovered_monster: MonsterView

@onready var _surface: ColorRect = $Surface
@onready var _surface_material: ShaderMaterial = _surface.material as ShaderMaterial
@onready var _shadow: Node2D = $PlanetShadow
@onready var _monster_layer: Node2D = $Monsters
@onready var _count_slider: HSlider = $Controls/Row/CountSlider
@onready var _count_label: Label = $Controls/Row/CountLabel
@onready var _import_button: Button = $Controls/Row/ImportButton
@onready var _reset_button: Button = $Controls/Row/ResetButton
@onready var _status_label: Label = $Status
@onready var _file_dialog: FileDialog = $ImportDialog


func _ready() -> void:
	get_window().min_size = Vector2i(780, 620)
	get_window().size = Vector2i(1280, 820)
	get_window().title = "Planet · Globe Preview"
	resized.connect(_update_layout)
	_count_slider.value = monster_count
	_count_slider.value_changed.connect(_on_count_changed)
	_import_button.pressed.connect(_open_import_dialog)
	_reset_button.pressed.connect(_reset_view)
	_file_dialog.file_selected.connect(_on_file_selected)
	if monster_texture != null:
		_set_monster_texture(monster_texture)
	elif ResourceLoader.exists(DEFAULT_TEXTURE_PATH):
		_set_monster_texture(load(DEFAULT_TEXTURE_PATH) as Texture2D)
	else:
		_status_label.text = "导入一张透明怪物图片，放到这颗星球上。"
	_rebuild_monsters()
	_update_layout()


func _process(_delta: float) -> void:
	var hovered: MonsterView = null if _dragging else _pick_monster(get_global_mouse_position())
	if hovered != _hovered_monster:
		_hovered_monster = hovered
		_update_feedback()
	var pointer_shape: Input.CursorShape = Input.CURSOR_ARROW
	if _dragging:
		pointer_shape = Input.CURSOR_DRAG
	elif _hovered_monster != null:
		pointer_shape = Input.CURSOR_POINTING_HAND
	elif get_global_mouse_position().distance_to(_planet_center) <= _planet_radius:
		pointer_shape = Input.CURSOR_MOVE
	Input.set_default_cursor_shape(pointer_shape)


func _input(event: InputEvent) -> void:
	if not _dragging:
		return
	if event is InputEventMouseButton:
		var button_event: InputEventMouseButton = event as InputEventMouseButton
		if button_event.button_index == MOUSE_BUTTON_LEFT and not button_event.pressed:
			_handle_mouse_button(button_event)
		elif (
			button_event.pressed
			and button_event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]
		):
			_handle_mouse_button(button_event)
	elif event is InputEventMouseMotion:
		var motion: InputEventMouseMotion = event as InputEventMouseMotion
		if motion.position.distance_to(_drag_start_mouse) > 5.0:
			_drag_moved = true
		var current_vector: Vector3 = GlobeMath.arcball_vector(
			motion.position, _planet_center, _planet_radius, _camera_distance, _focal_length
		)
		_orientation = GlobeMath.drag_orientation(
			_drag_start_vector, current_vector, _drag_start_orientation
		)
		_update_projection()
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		_handle_mouse_button(event as InputEventMouseButton)


func _handle_mouse_button(event: InputEventMouseButton) -> void:
	if event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			var over_globe: bool = event.position.distance_to(_planet_center) <= _planet_radius
			if not over_globe and _pick_monster(event.position) == null:
				return
			_dragging = true
			_drag_moved = false
			_capture_drag_anchor(event.position)
		elif _dragging:
			_dragging = false
			if not _drag_moved:
				_selected_monster = _pick_monster(event.position)
				_update_selection_caption()
				_update_feedback()
		get_viewport().set_input_as_handled()
	elif event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		var step: float = 1.12 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.12
		_zoom_at_pointer(step, event.position)
		get_viewport().set_input_as_handled()


func _capture_drag_anchor(screen_position: Vector2) -> void:
	_drag_start_mouse = screen_position
	_drag_start_vector = GlobeMath.arcball_vector(
		screen_position, _planet_center, _planet_radius, _camera_distance, _focal_length
	)
	_drag_start_orientation = _orientation


func _zoom_at_pointer(step: float, screen_position: Vector2) -> void:
	var anchor: Vector3 = GlobeMath.unproject_position(
		screen_position,
		_orientation,
		_planet_center,
		_planet_radius,
		_camera_distance,
		_focal_length
	)
	var maximum_zoom: float = sqrt(
		(
			(OVERVIEW_CAMERA_DISTANCE * OVERVIEW_CAMERA_DISTANCE - 1.0)
			/ (closest_camera_distance * closest_camera_distance - 1.0)
		)
	)
	_zoom = clampf(_zoom * step, 1.0, maximum_zoom)
	_update_layout()
	var target: Vector3 = GlobeMath.unproject_position(
		screen_position,
		Quaternion.IDENTITY,
		_planet_center,
		_planet_radius,
		_camera_distance,
		_focal_length
	)
	if anchor != Vector3.ZERO and target != Vector3.ZERO:
		var anchor_rotation: Quaternion = Quaternion(
			(_orientation * anchor).normalized(), target.normalized()
		)
		_orientation = (anchor_rotation * _orientation).normalized()
		_update_projection()
	if _dragging:
		_drag_moved = true
		_capture_drag_anchor(screen_position)


func _update_layout() -> void:
	var available_height: float = size.y - 154.0
	var available_width: float = size.x - 140.0
	_planet_center = Vector2(size.x * 0.5, (size.y - 142.0) * 0.5 + 26.0)
	var maximum_radius: float = minf(_planet_center.y - 72.0, size.y - 148.0 - _planet_center.y)
	_overview_radius = minf(minf(available_height * 0.425, available_width * 0.43), maximum_radius)
	_focal_length = (
		_overview_radius * sqrt(OVERVIEW_CAMERA_DISTANCE * OVERVIEW_CAMERA_DISTANCE - 1.0)
	)
	_camera_distance = sqrt(
		1.0 + (OVERVIEW_CAMERA_DISTANCE * OVERVIEW_CAMERA_DISTANCE - 1.0) / (_zoom * _zoom)
	)
	_planet_radius = _overview_radius * _zoom
	_surface.position = _planet_center - Vector2.ONE * _planet_radius
	_surface.size = Vector2.ONE * _planet_radius * 2.0
	_shadow.position = _planet_center + Vector2(0.0, _planet_radius * 1.04)
	_shadow.scale = Vector2.ONE * _planet_radius / 280.0
	_update_projection()
	if _dragging:
		_capture_drag_anchor(get_global_mouse_position())


func _update_projection() -> void:
	_surface_material.set_shader_parameter(
		"orientation", Vector4(_orientation.x, _orientation.y, _orientation.z, _orientation.w)
	)
	_surface_material.set_shader_parameter("camera_distance", _camera_distance)
	for monster: MonsterView in _monsters:
		var view_position: Vector3 = _orientation * monster.geographic_position
		var screen_position: Vector2 = GlobeMath.project_position(
			monster.geographic_position,
			_orientation,
			_planet_center,
			_planet_radius,
			_camera_distance,
			_focal_length
		)
		var camera_offset: Vector3 = Vector3(0.0, 0.0, _camera_distance) - view_position
		var facing: float = view_position.dot(camera_offset.normalized())
		var projection_scale: float = (
			(_overview_radius / 280.0)
			* (OVERVIEW_CAMERA_DISTANCE - 1.0)
			/ (_camera_distance - view_position.z)
		)
		monster.set_projected_position(screen_position, facing, projection_scale)


func _rebuild_monsters() -> void:
	_selected_monster = null
	_hovered_monster = null
	for monster: MonsterView in _monsters:
		monster.queue_free()
	_monsters.clear()
	var colony_centers: Array[Vector2] = [
		Vector2(0.31, -0.65),
		Vector2(-0.36, 0.67),
		Vector2(0.38, 2.25),
		Vector2(-0.27, -2.65),
	]
	for monster_index: int in range(monster_count):
		var monster: MonsterView = MONSTER_SCENE.instantiate() as MonsterView
		_monster_layer.add_child(monster)
		var colony_index: int = monster_index % colony_centers.size()
		var colony_member: int = monster_index / colony_centers.size()
		var colony_size: float = ceilf(float(monster_count) / float(colony_centers.size()))
		var angle: float = float(colony_member) * 2.399963
		var spread: float = 0.44 * sqrt((float(colony_member) + 0.5) / colony_size)
		var center: Vector2 = colony_centers[colony_index]
		monster.geographic_position = GlobeMath.geographic_position(
			center.x + sin(angle) * spread, center.y + cos(angle) * spread / cos(center.x)
		)
		if monster_index == 0:
			monster.geographic_position = LANDMARK_POSITION.normalized()
		monster.monster_number = monster_index + 1
		monster.configure(_display_texture, _alpha_mask, monster_height)
		_monsters.append(monster)
	_count_label.text = "怪物 %d" % monster_count
	_update_selection_caption()
	_update_projection()


func _pick_monster(screen_position: Vector2) -> MonsterView:
	var closest_monster: MonsterView = null
	for monster: MonsterView in _monsters:
		if monster.contains_screen_point(screen_position):
			if closest_monster == null or monster.z_index > closest_monster.z_index:
				closest_monster = monster
	return closest_monster


func _update_feedback() -> void:
	for monster: MonsterView in _monsters:
		monster.set_feedback(monster == _hovered_monster, monster == _selected_monster)


func _update_selection_caption() -> void:
	if _display_texture == null:
		_status_label.text = "导入一张透明怪物图片，放到这颗星球上。"
	elif _selected_monster != null:
		_status_label.text = "已选中怪物 %02d" % _selected_monster.monster_number
	else:
		_status_label.text = ""


func _on_count_changed(value: float) -> void:
	monster_count = int(value)
	_rebuild_monsters()


func _reset_view() -> void:
	_orientation = Quaternion.IDENTITY
	_zoom = 1.0
	_selected_monster = null
	_update_selection_caption()
	_update_feedback()
	_update_layout()


func _open_import_dialog() -> void:
	_file_dialog.popup_centered_ratio(0.70)


func _on_file_selected(path: String) -> void:
	if not _load_image(path):
		return
	for monster: MonsterView in _monsters:
		monster.configure(_display_texture, _alpha_mask, monster_height)
	_update_selection_caption()


func _load_image(path: String) -> bool:
	var image: Image = Image.new()
	var error: Error = image.load(path)
	if error != OK:
		_status_label.text = "图片未能打开，请选择 PNG 或 WebP。"
		return false
	return _set_monster_texture(ImageTexture.create_from_image(image))


func _set_monster_texture(texture: Texture2D) -> bool:
	var source_image: Image = texture.get_image()
	var source_mask: BitMap = BitMap.new()
	source_mask.create_from_image_alpha(source_image, 0.16)
	var content_rect: Rect2i = _content_rect(source_mask, source_image.get_used_rect())
	if content_rect.size.x < 1 or content_rect.size.y < 1:
		_status_label.text = "图片没有可见轮廓，请选择其他图片。"
		return false
	var atlas_texture: AtlasTexture = AtlasTexture.new()
	atlas_texture.atlas = texture
	atlas_texture.region = Rect2(content_rect)
	_display_texture = atlas_texture
	_alpha_mask = BitMap.new()
	_alpha_mask.create_from_image_alpha(_display_texture.get_image(), 0.16)
	return true


func _content_rect(alpha_mask: BitMap, initial_rect: Rect2i) -> Rect2i:
	var top: int = initial_rect.position.y
	var bottom: int = initial_rect.end.y - 1
	var left: int = initial_rect.position.x
	var right: int = initial_rect.end.x - 1
	while top <= bottom and not _row_has_alpha(alpha_mask, top, left, right):
		top += 1
	while bottom >= top and not _row_has_alpha(alpha_mask, bottom, left, right):
		bottom -= 1
	while left <= right and not _column_has_alpha(alpha_mask, left, top, bottom):
		left += 1
	while right >= left and not _column_has_alpha(alpha_mask, right, top, bottom):
		right -= 1
	return Rect2i(left, top, maxi(0, right - left + 1), maxi(0, bottom - top + 1))


func _row_has_alpha(alpha_mask: BitMap, row: int, left: int, right: int) -> bool:
	for column: int in range(left, right + 1):
		if alpha_mask.get_bitv(Vector2i(column, row)):
			return true
	return false


func _column_has_alpha(alpha_mask: BitMap, column: int, top: int, bottom: int) -> bool:
	for row: int in range(top, bottom + 1):
		if alpha_mask.get_bitv(Vector2i(column, row)):
			return true
	return false
