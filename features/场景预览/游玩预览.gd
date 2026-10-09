extends "res://scripts/disk_demo.gd"

@export var start_in_overview: bool = false

@onready var _near_background: Node2D = $美术背景/地壳裁剪/画布/近景背景
@onready var _overview_background: Node2D = $美术背景/地壳裁剪/画布/全景背景
@onready var _switch_button: Button = $预览导航/切换视角


func _ready() -> void:
	super._ready()
	_view.view_changed.connect(_sync_art)
	get_viewport().size_changed.connect(_fit_background)
	RenderingServer.set_default_clear_color(Color.BLACK)
	_fit_background()
	if start_in_overview:
		_view.zoom_steps(-1.0)
	_sync_art()


func _fit_background() -> void:
	var interface_scale: Vector2 = _layout.scale
	var menu_button: Button = $预览导航/返回主菜单
	menu_button.scale = interface_scale
	menu_button.position = Vector2(28.0, 204.0) * interface_scale
	_switch_button.scale = interface_scale
	_switch_button.position = Vector2(174.0, 204.0) * interface_scale


func _sync_art() -> void:
	_near_background.visible = not _view.is_overview()
	_overview_background.visible = _view.is_overview()
	_switch_button.text = "近景" if _view.is_overview() else "全景"


func _switch_view() -> void:
	_view.zoom_steps(1.0 if _view.is_overview() else -1.0)


func _return_to_menu() -> void:
	get_tree().change_scene_to_file.call_deferred("res://scenes/主菜单/主菜单.tscn")
