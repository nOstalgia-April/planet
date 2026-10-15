extends Control

enum PreviewMode { ORIGINAL, GLOW, COMPLETE }

@onready var _selector: OptionButton = $PreviewControls/Selector
@onready var _glow: CanvasItem = $Menu/画布/Atmosphere/AmbientGlow
@onready var _far_motes: CanvasItem = $Menu/画布/Atmosphere/FarMotes
@onready var _near_motes: CanvasItem = $Menu/画布/Atmosphere/NearMotes
@onready var _vignette: CanvasItem = $Menu/画布/Atmosphere/Vignette


func _ready() -> void:
	_selector.item_selected.connect(_set_preview_mode)
	_set_preview_mode(PreviewMode.COMPLETE)


func _set_preview_mode(index: int) -> void:
	_glow.visible = index != PreviewMode.ORIGINAL
	var complete: bool = index == PreviewMode.COMPLETE
	_far_motes.visible = complete
	_near_motes.visible = complete
	_vignette.visible = complete
