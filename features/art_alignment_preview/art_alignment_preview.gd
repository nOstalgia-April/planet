extends "res://features/场景预览/游玩预览.gd"

const SETTINGS_PATH: String = "res://resources/art_presentation.tres"
const SPECIES_NAMES: Array[String] = ["史莱姆", "黏液", "地鼠"]
const STAGES: Array[String] = ["初始", "培育", "强化培育", "自动化花"]
const DrillView = preload("res://scripts/drill_monster.gd")
const NativeGallery = preload("res://features/art_alignment_preview/native_size_gallery.gd")
const ItemArt = preload("res://scripts/物品动画/动画物件.gd")
const SourceProjection = preload("res://scripts/surface_projection.gd")

var settings: ArtPresentationSettings
var _shared_settings: ArtPresentationSettings
var _loading_controls: bool = false
var _native_sizes: bool = false
var _source_view_scale: float = 1.0

@onready var _target: OptionButton = %Target
@onready var _stage: OptionButton = %Stage
@onready var _scale_input: SpinBox = %ScaleInput
@onready var _sink_input: SpinBox = %SinkInput
@onready var _seating: CheckButton = %Seating
@onready var _status: Label = %AlignmentStatus
@onready var _panel: Control = %AlignmentPanel
@onready var _expand_menu: Button = %ExpandMenu
@onready var _native_gallery: NativeGallery = %NativeGallery


func _ready() -> void:
	super._ready()
	get_window().title = "巢穴与怪物尺寸调节"
	_shared_settings = load(SETTINGS_PATH) as ArtPresentationSettings
	settings = _shared_settings.duplicate(true) as ArtPresentationSettings
	run.set_process(false)
	_layout.set_process(false)
	set_process(false)
	_layout.hide()
	_pipe.hide()
	_net.hide()
	for nest: NestView in _nest_views:
		nest.queue_free()
	_nest_views.clear()
	for slime: PrototypeSlime in _slimes:
		slime.queue_free()
	_slimes.clear()
	for area: NestMucusArea in _nest_mucus_areas:
		area.queue_free()
	_nest_mucus_areas.clear()
	for label: String in ["全部", "所有巢穴", "所有怪物"]:
		_target.add_item(label)
	for species_index: int in range(3):
		for stage_index: int in range(4):
			_target.add_item("%s · %s" % [SPECIES_NAMES[species_index], STAGES[stage_index]])
	for label: String in SPECIES_NAMES:
		_target.add_item(label + "怪物")
	for label: String in STAGES:
		_stage.add_item(label)
	_stage.select(1)
	for species_index: int in range(3):
		var nest: NestView = nest_scene.instantiate() as NestView
		nest.surface = _planet
		nest.art_settings = settings
		_nests.add_child(nest)
		for art: ItemArt in nest._art._get_art_items():
			_use_source_size(art)
		nest.configure_species(species_index)
		nest.setup(species_index + 1)
		nest.update_state(1, false, 3)
		nest.presentation_scale = _view.near_nest_scale
		_nest_views.append(nest)
		var monster_scene: PackedScene = DRILL_SCENE if species_index == 2 else slime_scene
		var monster: PrototypeSlime = monster_scene.instantiate() as PrototypeSlime
		monster.art_settings = settings
		_slime_root.add_child(monster)
		if species_index != 2:
			monster.slime_art_scale = 1.0
		monster.setup(species_index + 1, Vector2.UP * _planet.radius, _planet)
		monster.configure_species(species_index as PrototypeSlime.Species, false, 2)
		monster.presentation_scale = _view.near_slime_scale
		monster.set_process(false)
		if species_index == 2:
			var drill: DrillView = monster as DrillView
			drill.phase = DrillView.Phase.EXPOSED
			drill.art.play_clip(&"夹夹")
		_slimes.append(monster)
	_target.item_selected.connect(_select_target)
	_stage.item_selected.connect(_change_stage)
	_scale_input.value_changed.connect(_edit_scale)
	_sink_input.value_changed.connect(_edit_sink)
	_seating.toggled.connect(_toggle_seating)
	%Save.pressed.connect(_save_settings)
	%Reset.pressed.connect(_reset_settings)
	%Native.pressed.connect(_toggle_native_sizes)
	%Menu.pressed.connect(_return_to_menu)
	%Collapse.pressed.connect(_toggle_menu)
	_expand_menu.pressed.connect(_toggle_menu)
	%Spawn.pressed.connect(_play_spawn)
	%Rotate.value_changed.connect(_rotate_world)
	get_viewport().size_changed.connect(_fit_alignment)
	_view.projection_changed.connect(_refresh_samples)
	_fit_alignment()
	_select_target(0)
	_refresh_samples()


func _use_source_size(art: ItemArt) -> void:
	# Edit only this preview instance: gameplay keeps its shared calibrated resources.
	var library: AnimationLibrary = (
		art.animation_player.get_animation_library(&"").duplicate(true) as AnimationLibrary
	)
	for clip: StringName in library.get_animation_list():
		var animation: Animation = library.get_animation(clip)
		var scale_track: int = animation.find_track(NodePath("画面/贴图:scale"), Animation.TYPE_VALUE)
		var position_track: int = animation.find_track(
			NodePath("画面/贴图:position"), Animation.TYPE_VALUE
		)
		assert(scale_track >= 0 and position_track >= 0, "Source art needs scale and anchor tracks.")
		for key: int in range(animation.track_get_key_count(position_track)):
			var time: float = animation.track_get_key_time(position_track, key)
			var old_scale: Vector2 = animation.value_track_interpolate(scale_track, time)
			var anchor: Vector2 = animation.track_get_key_value(position_track, key)
			animation.track_set_key_value(position_track, key, anchor / old_scale)
		for key: int in range(animation.track_get_key_count(scale_track)):
			animation.track_set_key_value(scale_track, key, Vector2.ONE)
	art.animation_player.stop()
	art.animation_player.remove_animation_library(&"")
	art.animation_player.add_animation_library(&"", library)
	var sprite: Sprite2D = art.get_node("画面/贴图") as Sprite2D
	sprite.position /= sprite.scale
	sprite.scale = Vector2.ONE
	art.scale = Vector2.ONE


func _input(_event: InputEvent) -> void:
	pass


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_return_to_menu()
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_N:
		_toggle_native_sizes()


func _fit_alignment() -> void:
	var factor: float = minf(
		get_viewport_rect().size.x / 1280.0, get_viewport_rect().size.y / 800.0
	)
	_panel.scale = Vector2.ONE * factor
	_panel.position = Vector2(24.0, 20.0) * factor
	_expand_menu.scale = Vector2.ONE * factor
	_expand_menu.position = _panel.position
	var pixel_scale: float = get_viewport_rect().size.x / float(get_window().size.x)
	var header: Control = _panel if _panel.visible else _expand_menu
	var header_bottom: float = (header.position.y + header.size.y * factor) / pixel_scale
	var gallery_top: float = (
		maxf(260.0, header_bottom + 16.0) if _panel.visible else header_bottom + 16.0
	)
	_native_gallery.scale = Vector2.ONE * pixel_scale
	_native_gallery.position = Vector2(24.0, gallery_top) * pixel_scale
	_native_gallery.size = (
		get_viewport_rect().size / pixel_scale - Vector2(48.0, gallery_top + 24.0)
	)
	_place_samples()


func _toggle_menu() -> void:
	_panel.visible = not _panel.visible
	_expand_menu.visible = not _panel.visible
	_fit_alignment()


func _place_samples() -> void:
	if _nest_views.size() != 3:
		return
	for index: int in range(3):
		var angle: float = -PI * 0.5 + (float(index) - 1.0) * 0.46 - _world.rotation
		var nest: NestView = _nest_views[index]
		nest.position = _planet.get_nest_position(angle)
		nest.rotation = _planet.get_nest_rotation(angle)
		var monster: PrototypeSlime = _slimes[index]
		monster.position = _planet.project_to_surface(
			nest.position - nest.position.normalized() * 32.0
		)
		monster.refresh_surface_bounds()
	_refresh_samples()


func _rotate_world(value: float) -> void:
	_world.rotation = value
	_place_samples()


func _select_target(index: int) -> void:
	if index >= 3 and index < 15:
		_stage.select((index - 3) % 4)
		_change_stage(_stage.selected)
	_loading_controls = true
	_scale_input.value = _get_scale(index)
	_sink_input.value = _get_sink(index)
	_seating.button_pressed = settings.curved_seating
	_loading_controls = false
	if _native_sizes:
		_native_gallery.configure(_nest_views, _slimes, index)


func _get_scale(index: int) -> float:
	match index:
		0:
			return settings.all_scale
		1:
			return settings.nest_scale
		2:
			return settings.monster_scale
	return settings.nest_scales[index - 3] if index < 15 else settings.monster_scales[index - 15]


func _get_sink(index: int) -> float:
	match index:
		0:
			return settings.all_sink
		1:
			return settings.nest_sink
		2:
			return settings.monster_sink
	return settings.nest_sinks[index - 3] if index < 15 else settings.monster_sinks[index - 15]


func _edit_scale(value: float) -> void:
	if _loading_controls:
		return
	match _target.selected:
		0:
			settings.all_scale = value
		1:
			settings.nest_scale = value
		2:
			settings.monster_scale = value
		_:
			if _target.selected < 15:
				settings.nest_scales[_target.selected - 3] = value
			else:
				settings.monster_scales[_target.selected - 15] = value
	_refresh_samples()


func _edit_sink(value: float) -> void:
	if _loading_controls:
		return
	match _target.selected:
		0:
			settings.all_sink = value
		1:
			settings.nest_sink = value
		2:
			settings.monster_sink = value
		_:
			if _target.selected < 15:
				settings.nest_sinks[_target.selected - 3] = value
			else:
				settings.monster_sinks[_target.selected - 15] = value
	_refresh_samples()


func _toggle_seating(value: bool) -> void:
	if _loading_controls:
		return
	settings.curved_seating = value
	_refresh_samples()


func _change_stage(value: int) -> void:
	for nest: NestView in _nest_views:
		nest.update_state(value, value == 3, 3, false)
	_refresh_samples()
	if _native_sizes:
		_native_gallery.configure(_nest_views, _slimes, _target.selected)


func _toggle_native_sizes() -> void:
	_native_sizes = not _native_sizes
	_fit_alignment()
	_native_gallery.visible = _native_sizes
	_nests.visible = not _native_sizes
	_slime_root.visible = not _native_sizes
	%ActivityOutline.visible = not _native_sizes
	%Native.text = "返回星球预览" if _native_sizes else "原图 100%"
	%Save.disabled = _native_sizes
	%Spawn.disabled = _native_sizes
	_scale_input.editable = not _native_sizes
	_sink_input.editable = not _native_sizes
	_seating.disabled = _native_sizes
	if _native_sizes:
		_native_gallery.configure(_nest_views, _slimes, _target.selected)
		_status.text = "PNG 原图 100% · 保留透明留白 · 大图可滚动查看 · 不改保存倍率"
	else:
		_refresh_samples()


func _play_spawn() -> void:
	for nest: NestView in _nest_views:
		if _stage.selected == 3:
			nest.pulse_automatic()
		else:
			nest.pulse_spawn()


func _refresh_samples() -> void:
	# Cancel both the world camera and viewport stretch, so one PNG pixel is one window pixel.
	var screen_ratio: float = float(get_window().size.x) / get_viewport_rect().size.x
	var source_transform: Transform2D = (
		_world.get_global_transform_with_canvas()
		* SourceProjection.get_visual_compensation(_world)
	)
	_source_view_scale = 1.0 / (source_transform.x.length() * screen_ratio)
	_view.near_nest_scale = Vector2.ONE * _source_view_scale
	_view.near_slime_scale = _source_view_scale
	for nest: NestView in _nest_views:
		nest.presentation_scale = Vector2.ONE * _source_view_scale
		nest.refresh_presentation()
	for monster: PrototypeSlime in _slimes:
		monster.presentation_scale = _source_view_scale
		monster.refresh_presentation()
	%ActivityOutline.queue_redraw()
	_status.text = (
		"PNG 原图 100% · 保留透明留白 · 大图可滚动查看"
		if _native_sizes
		else "原素材显示尺寸 · 正值下沉，负值抬起 · 尚未保存"
	)


func _save_settings() -> void:
	var result: Error = ResourceSaver.save(settings, SETTINGS_PATH)
	if result == OK:
		_shared_settings.copy_from(settings)
		_status.text = "已保存，返回主菜单后开始新游戏生效"
	else:
		_status.text = "保存失败：%s" % error_string(result)


func _reset_settings() -> void:
	settings = ArtPresentationSettings.new()
	for nest: NestView in _nest_views:
		nest.art_settings = settings
	for monster: PrototypeSlime in _slimes:
		monster.art_settings = settings
	_select_target(_target.selected)
	_refresh_samples()


func _return_to_menu() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file.call_deferred("res://scenes/主菜单/主菜单.tscn")
