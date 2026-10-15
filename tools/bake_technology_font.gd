extends SceneTree

# Run headless with --script res://tools/bake_technology_font.gd after changing
# technology copy or the source fonts. Only currently used characters are baked.
const FontCache = preload("res://fonts/technology_font_cache.gd")
const SOURCES: PackedStringArray = [
	"res://fonts/Oldenburg/Oldenburg-Regular.ttf",
	"res://fonts/站酷小薇LOGO体/站酷小薇LOGO体.otf",
	"res://fonts/NotoSansSC-Regular.otf",
]
const CACHES: PackedStringArray = [
	"res://fonts/technology_cache/oldenburg.res",
	"res://fonts/technology_cache/chinese.res",
	"res://fonts/technology_cache/fallback.res",
]
const TEXT_SOURCES: PackedStringArray = [
	"res://scripts/ui/technology_page.gd",
	"res://scripts/ui/technology_node.gd",
	"res://scripts/ui/interactive_technology_page.gd",
	"res://scenes/ui/technology_page.tscn",
	"res://scenes/ui/technology_node.tscn",
	"res://scripts/prototype_run.gd",
]


func _initialize() -> void:
	_bake.call_deferred()


func _bake() -> void:
	var fonts: Array[FontFile] = []
	for path: String in SOURCES:
		fonts.append(FontCache.make_font(load(path) as FontFile))
	var characters: Dictionary[int, bool] = {}
	for codepoint: int in range(32, 127):
		characters[codepoint] = true
	for path: String in TEXT_SOURCES:
		var text: String = FileAccess.get_file_as_string(path)
		assert(not text.is_empty(), "Missing font text source: " + path)
		for index: int in range(text.length()):
			var codepoint: int = text.unicode_at(index)
			if codepoint > 126:
				characters[codepoint] = true
	var sorted_characters: Array[int] = characters.keys()
	sorted_characters.sort()
	var size: Vector2i = Vector2i(FontCache.MSDF_SIZE, 0)
	for codepoint: int in sorted_characters:
		for font: FontFile in fonts:
			if font.has_char(codepoint):
				font.render_range(0, size, codepoint, codepoint)
				break
	assert(DirAccess.make_dir_recursive_absolute(CACHES[0].get_base_dir()) == OK)
	for index: int in range(fonts.size()):
		var font: FontFile = fonts[index]
		var cache: FontFile = FontFile.new()
		cache.multichannel_signed_distance_field = true
		cache.msdf_size = FontCache.MSDF_SIZE
		cache.msdf_pixel_range = FontCache.MSDF_PIXEL_RANGE
		FontCache.copy_cache(font, cache)
		assert(cache.data.is_empty(), "Cache must not duplicate the original font file.")
		assert(ResourceSaver.save(cache, CACHES[index], ResourceSaver.FLAG_COMPRESS) == OK)
		var saved: FontFile = (
			ResourceLoader.load(CACHES[index], "FontFile", ResourceLoader.CACHE_MODE_IGNORE)
			as FontFile
		)
		assert(saved.data.is_empty())
		var restored: FontFile = FontCache.make_font(load(SOURCES[index]) as FontFile)
		FontCache.copy_cache(saved, restored)
		_verify_cache(font, restored, size)
		print(
			(
				"FONT_CACHE %s glyphs=%d textures=%d bytes=%d original_data_bytes=%d"
				% [
					CACHES[index],
					font.get_glyph_list(0, size).size(),
					font.get_texture_count(0, size),
					FileAccess.get_file_as_bytes(CACHES[index]).size(),
					saved.data.size()
				]
			)
		)
	print("PASS: technology MSDF cache round-trip preserved all glyph metrics and atlas pixels.")
	quit()


func _verify_cache(source: FontFile, restored: FontFile, size: Vector2i) -> void:
	assert(source.get_glyph_list(0, size) == restored.get_glyph_list(0, size))
	assert(source.get_texture_count(0, size) == restored.get_texture_count(0, size))
	for index: int in range(source.get_texture_count(0, size)):
		var expected: Image = source.get_texture_image(0, size, index)
		var actual: Image = restored.get_texture_image(0, size, index)
		assert(expected.get_size() == actual.get_size())
		assert(expected.get_format() == actual.get_format())
		assert(expected.get_data() == actual.get_data(), "MSDF atlas pixels changed during save.")
		assert(
			(
				source.get_texture_offsets(0, size, index)
				== restored.get_texture_offsets(0, size, index)
			)
		)
	for glyph: int in source.get_glyph_list(0, size):
		assert(
			(
				source.get_glyph_advance(0, size.x, glyph)
				== restored.get_glyph_advance(0, size.x, glyph)
			)
		)
		assert(source.get_glyph_offset(0, size, glyph) == restored.get_glyph_offset(0, size, glyph))
		assert(source.get_glyph_size(0, size, glyph) == restored.get_glyph_size(0, size, glyph))
		assert(
			source.get_glyph_uv_rect(0, size, glyph) == restored.get_glyph_uv_rect(0, size, glyph)
		)
		assert(
			(
				source.get_glyph_texture_idx(0, size, glyph)
				== restored.get_glyph_texture_idx(0, size, glyph)
			)
		)
