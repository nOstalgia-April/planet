extends Node2D

const ClaimedCrust = preload("res://scripts/claimed_crust.gd")
const FlowerArt = preload("res://scripts/物品动画/动画物件.gd")
const REFERENCE_SIZE: Vector2 = Vector2(1920.0, 1080.0)
const PLANET_CENTER: Vector2 = Vector2(972.5, 1846.9)
const PLANET_RADIUS: float = 1322.0

@export_range(1.0, 15.0, 0.1) var spread_seconds: float = 7.8
@export var autoplay: bool = true

@onready var _canvas: Node2D = $Canvas
@onready var _crust: ClaimedCrust = $Canvas/染色地壳
@onready var _flower: FlowerArt = $Canvas/花
@onready var _mucus_flower: FlowerArt = $Canvas/黏液花
@onready var _controls: Control = $Canvas/Controls
@onready var _compare_button: Button = $Canvas/Controls/Panel/Rows/Buttons/Compare
@onready var _progress: HSlider = $Canvas/Controls/Panel/Rows/Sizes/Progress
@onready var _pink_slider: HSlider = $Canvas/Controls/Panel/Rows/Sizes/PinkSize
@onready var _blue_slider: HSlider = $Canvas/Controls/Panel/Rows/Sizes/BlueSize
@onready var _mode: OptionButton = $Canvas/Controls/Panel/Rows/Buttons/Mode
@onready var _order_button: Button = $Canvas/Controls/Panel/Rows/Buttons/Order

var _spread: Tween
var _preview_progress: float = 1.0


func _ready() -> void:
	RenderingServer.set_default_clear_color(Color.BLACK)
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)
	_flower.clip_finished.connect(_on_flower_finished.bind(_flower))
	_mucus_flower.clip_finished.connect(_on_flower_finished.bind(_mucus_flower))
	_flower.play_clip(&"待机")
	_mucus_flower.play_clip(&"待机")
	_flower.position = (
		PLANET_CENTER
		+ Vector2(_crust.pink_source.x, _crust.pink_source.y - 1.0) * PLANET_RADIUS
		+ Vector2(0.0, 18.0)
	)
	_mucus_flower.position = (
		PLANET_CENTER
		+ Vector2(_crust.blue_source.x, _crust.blue_source.y - 1.0) * PLANET_RADIUS
		+ Vector2(0.0, 18.0)
	)
	_flower.rotation = asin(_crust.pink_source.x)
	_mucus_flower.rotation = asin(_crust.blue_source.x)
	get_viewport().size_changed.connect(_fit_canvas)
	_fit_canvas()
	_sync_controls()
	_apply_progress(1.0)
	if autoplay:
		replay_claim()


func _fit_canvas() -> void:
	var viewport_size: Vector2 = get_viewport_rect().size
	var factor: float = minf(viewport_size.x / REFERENCE_SIZE.x, viewport_size.y / REFERENCE_SIZE.y)
	_canvas.scale = Vector2.ONE * factor
	_canvas.position = (viewport_size - REFERENCE_SIZE * factor) * 0.5


func replay_claim() -> void:
	_stop_spread()
	_flower.play_clip(&"产出")
	_mucus_flower.play_clip(&"产出")
	_apply_progress(0.0)
	_spread = create_tween()
	_spread.tween_method(_apply_progress, 0.0, 1.0, spread_seconds)
	_spread.finished.connect(_sync_controls)
	_compare_button.text = "查看原色"


func set_claim_progress(value: float) -> void:
	_stop_spread()
	_apply_progress(clampf(value, 0.0, 1.0))
	_sync_controls()


func set_preview_mode(mode: int) -> void:
	_mode.select(mode)
	_flower.visible = mode != 2
	_mucus_flower.visible = mode != 1
	_apply_progress(_preview_progress)


func set_patch_sizes(pink: float, blue: float) -> void:
	_crust.pink_size = pink
	_crust.blue_size = blue
	_sync_controls()


func randomize_patches() -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	_crust.shape_seed += 37
	rng.seed = _crust.shape_seed
	set_patch_sizes(rng.randf_range(0.6, 1.3), rng.randf_range(0.6, 1.3))
	replay_claim()


func set_controls_visible(value: bool) -> void:
	_controls.visible = value


func swap_coverage() -> void:
	_crust.mucus_on_top = not _crust.mucus_on_top
	_order_button.text = "蓝盖粉 ⇄" if _crust.mucus_on_top else "粉盖蓝 ⇄"
	replay_claim()


func _apply_progress(value: float) -> void:
	_preview_progress = value
	var earlier: float = clampf((value - 0.06) / 0.37, 0.0, 1.0)
	var later: float = clampf((value - 0.21) / 0.42, 0.0, 1.0)
	var first_flower: float = smoothstep(0.0, 0.06, value)
	var second_flower: float = smoothstep(0.15, 0.21, value)
	var pink_appearance: float = first_flower if _crust.mucus_on_top else second_flower
	var blue_appearance: float = second_flower if _crust.mucus_on_top else first_flower
	_crust.claim_progress = earlier if _crust.mucus_on_top else later
	_crust.mucus_progress = later if _crust.mucus_on_top else earlier
	# No outlet moves until BOTH spreading fronts have settled.
	var drips: float = clampf((value - 0.70) / 0.30, 0.0, 1.0)
	var drip_amount: Vector2 = Vector2.ONE * drips
	if _mode.selected == 1:
		_crust.claim_progress = clampf((value - 0.06) / 0.57, 0.0, 1.0)
		_crust.mucus_progress = 0.0
		drip_amount.y = 0.0
		pink_appearance = first_flower
	elif _mode.selected == 2:
		_crust.claim_progress = 0.0
		_crust.mucus_progress = clampf((value - 0.06) / 0.57, 0.0, 1.0)
		drip_amount.x = 0.0
		blue_appearance = first_flower
	_crust.drip_progress = drip_amount
	_flower.visible = _mode.selected != 2 and pink_appearance > 0.001
	_mucus_flower.visible = _mode.selected != 1 and blue_appearance > 0.001
	_flower.scale = Vector2.ONE * 2.12 * lerpf(0.65, 1.0, pink_appearance)
	_mucus_flower.scale = Vector2.ONE * 1.9 * lerpf(0.65, 1.0, blue_appearance)
	_flower.modulate.a = pink_appearance
	_mucus_flower.modulate.a = blue_appearance
	_progress.set_value_no_signal(value)


func _apply_sizes(_changed: bool) -> void:
	set_patch_sizes(_pink_slider.value, _blue_slider.value)
	replay_claim()


func _toggle_comparison() -> void:
	set_claim_progress(1.0 if _preview_progress < 0.01 else 0.0)


func _sync_controls() -> void:
	_compare_button.text = "查看染色" if _preview_progress < 0.01 else "查看原色"
	_progress.set_value_no_signal(_preview_progress)
	_pink_slider.set_value_no_signal(_crust.pink_size)
	_blue_slider.set_value_no_signal(_crust.blue_size)


func _stop_spread() -> void:
	if _spread != null:
		_spread.kill()
		_spread = null


func _on_flower_finished(_clip: StringName, flower: FlowerArt) -> void:
	flower.play_clip(&"待机")


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_SPACE:
				replay_claim()
			KEY_C:
				_toggle_comparison()
			KEY_R:
				randomize_patches()
			KEY_H:
				set_controls_visible(not _controls.visible)
			KEY_ESCAPE:
				_return_to_menu()
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		for flower in [_flower, _mucus_flower]:
			if (
				flower.visible
				and Rect2(-75.0, -145.0, 150.0, 160.0).has_point(flower.get_local_mouse_position())
			):
				replay_claim()
				break


func _return_to_menu() -> void:
	get_tree().change_scene_to_file.call_deferred("res://scenes/主菜单/主菜单.tscn")
