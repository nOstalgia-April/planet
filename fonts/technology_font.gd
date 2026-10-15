@tool
extends FontVariation

const FontCache = preload("res://fonts/technology_font_cache.gd")


func _init() -> void:
	base_font = _smooth_font(
		preload("res://fonts/Oldenburg/Oldenburg-Regular.ttf"),
		preload("res://fonts/technology_cache/oldenburg.res")
	)
	fallbacks = [
		_smooth_font(
			preload("res://fonts/站酷小薇LOGO体/站酷小薇LOGO体.otf"),
			preload("res://fonts/technology_cache/chinese.res")
		),
		_smooth_font(
			preload("res://fonts/NotoSansSC-Regular.otf"),
			preload("res://fonts/technology_cache/fallback.res")
		),
	]


func _smooth_font(source: FontFile, cache: FontFile) -> FontFile:
	var font: FontFile = FontCache.make_font(source)
	FontCache.copy_cache(cache, font)
	return font
