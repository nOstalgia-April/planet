@tool
extends FontVariation


func _init() -> void:
	base_font = _smooth_font(preload("res://fonts/Oldenburg/Oldenburg-Regular.ttf"))
	fallbacks = [
		_smooth_font(preload("res://fonts/站酷小薇LOGO体/站酷小薇LOGO体.otf")),
		_smooth_font(preload("res://fonts/NotoSansSC-Regular.otf")),
	]


func _smooth_font(source: FontFile) -> FontFile:
	var font: FontFile = source.duplicate() as FontFile
	font.multichannel_signed_distance_field = true
	font.msdf_size = 64
	font.msdf_pixel_range = 16
	return font
