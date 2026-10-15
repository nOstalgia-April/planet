extends SceneTree

const FontCache = preload("res://fonts/technology_font_cache.gd")
const TechnologyFont: FontVariation = preload("res://fonts/technology_font.tres")
const SOURCES: Array[FontFile] = [
	preload("res://fonts/Oldenburg/Oldenburg-Regular.ttf"),
	preload("res://fonts/站酷小薇LOGO体/站酷小薇LOGO体.otf"),
	preload("res://fonts/NotoSansSC-Regular.otf"),
]
const SAMPLE: String = "基础价值 吸取速率 巢穴培育 0123456789 Lv.3/7 ✓ MAX 连击爬梯 捕网大小 自动产糖"


func _initialize() -> void:
	_run_checks.call_deferred()


func _run_checks() -> void:
	var reference: FontVariation = FontVariation.new()
	reference.base_font = FontCache.make_font(SOURCES[0])
	reference.fallbacks = [FontCache.make_font(SOURCES[1]), FontCache.make_font(SOURCES[2])]
	var fonts: Array[FontFile] = [
		TechnologyFont.base_font as FontFile,
		TechnologyFont.fallbacks[0] as FontFile,
		TechnologyFont.fallbacks[1] as FontFile,
	]
	var size: Vector2i = Vector2i(FontCache.MSDF_SIZE, 0)
	for index: int in range(fonts.size()):
		assert(fonts[index].data == SOURCES[index].data)
		assert(fonts[index].multichannel_signed_distance_field)
		assert(fonts[index].msdf_size == 64 and fonts[index].msdf_pixel_range == 16)
		assert(not fonts[index].get_glyph_list(0, size).is_empty())
	var started: int = Time.get_ticks_usec()
	var cached_size: Vector2 = TechnologyFont.get_string_size(
		SAMPLE, HORIZONTAL_ALIGNMENT_LEFT, -1, 19
	)
	var cached_ms: float = float(Time.get_ticks_usec() - started) / 1000.0
	started = Time.get_ticks_usec()
	var reference_size: Vector2 = reference.get_string_size(
		SAMPLE, HORIZONTAL_ALIGNMENT_LEFT, -1, 19
	)
	var reference_ms: float = float(Time.get_ticks_usec() - started) / 1000.0
	assert(cached_size.is_equal_approx(reference_size))
	for font_size: int in [13, 14, 17, 21, 38]:
		assert(
			(
				TechnologyFont
				. get_string_size(SAMPLE, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
				. is_equal_approx(
					reference.get_string_size(SAMPLE, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
				)
			)
		)
	var fallback: FontFile = fonts[2]
	var additional_character: int = "龘".unicode_at(0)
	assert(fallback.has_char(additional_character))
	var before: int = fallback.get_glyph_list(0, size).size()
	fallback.render_range(0, size, additional_character, additional_character)
	assert(
		fallback.get_glyph_list(0, size).size() > before,
		"New characters must still render dynamically."
	)
	print(
		(
			"PASS: technology font retains original sources, fallback, MSDF settings and text sizes; cached first layout %.2f ms vs uncached %.2f ms; unbaked glyph renders."
			% [cached_ms, reference_ms]
		)
	)
	quit()
