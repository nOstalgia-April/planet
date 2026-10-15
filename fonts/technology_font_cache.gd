@tool
extends RefCounted

# Cache files contain only losslessly saved glyph atlases and metrics. The original
# font data stays in its imported font and remains available for newly added text.
const MSDF_SIZE: int = 64
const MSDF_PIXEL_RANGE: int = 16


static func make_font(source: FontFile) -> FontFile:
	var font: FontFile = source.duplicate() as FontFile
	font.multichannel_signed_distance_field = true
	font.msdf_size = MSDF_SIZE
	font.msdf_pixel_range = MSDF_PIXEL_RANGE
	return font


static func copy_cache(source: FontFile, target: FontFile) -> void:
	assert(source.multichannel_signed_distance_field and target.multichannel_signed_distance_field)
	assert(source.msdf_size == target.msdf_size)
	assert(source.msdf_pixel_range == target.msdf_pixel_range)
	for size: Vector2i in source.get_size_cache_list(0):
		target.set_cache_ascent(0, size.x, source.get_cache_ascent(0, size.x))
		target.set_cache_descent(0, size.x, source.get_cache_descent(0, size.x))
		target.set_cache_underline_position(
			0, size.x, source.get_cache_underline_position(0, size.x)
		)
		target.set_cache_underline_thickness(
			0, size.x, source.get_cache_underline_thickness(0, size.x)
		)
		target.set_cache_scale(0, size.x, source.get_cache_scale(0, size.x))
		for index: int in range(source.get_texture_count(0, size)):
			target.set_texture_image(0, size, index, source.get_texture_image(0, size, index))
			target.set_texture_offsets(0, size, index, source.get_texture_offsets(0, size, index))
		for glyph: int in source.get_glyph_list(0, size):
			target.set_glyph_advance(0, size.x, glyph, source.get_glyph_advance(0, size.x, glyph))
			target.set_glyph_offset(0, size, glyph, source.get_glyph_offset(0, size, glyph))
			target.set_glyph_size(0, size, glyph, source.get_glyph_size(0, size, glyph))
			target.set_glyph_uv_rect(0, size, glyph, source.get_glyph_uv_rect(0, size, glyph))
			target.set_glyph_texture_idx(
				0, size, glyph, source.get_glyph_texture_idx(0, size, glyph)
			)
		for pair: Vector2i in source.get_kerning_list(0, size.x):
			target.set_kerning(0, size.x, pair, source.get_kerning(0, size.x, pair))
