extends RefCounted

# Retain the existing procedural art, but share its idle body between actors.
# Six pixels per world unit keeps edges clear at the near-view camera scale.
const RASTER_SCALE: float = 6.0
const BODY_POINTS: Array[Vector2] = [
	Vector2(-0.95, -0.08),
	Vector2(-1.00, -0.44),
	Vector2(-0.77, -0.98),
	Vector2(-0.52, -1.27),
	Vector2(-0.16, -1.39),
	Vector2(0.15, -1.48),
	Vector2(0.39, -1.32),
	Vector2(0.74, -1.08),
	Vector2(0.95, -0.57),
	Vector2(1.00, -0.20),
	Vector2(0.77, 0.05),
	Vector2(0.41, 0.12),
	Vector2(0.08, 0.05),
	Vector2(-0.25, 0.11),
	Vector2(-0.62, 0.08),
]

static var _textures: Dictionary = {}
static var _shadows: Dictionary = {}


static func get_body_rect(size: float) -> Rect2:
	return Rect2(Vector2(-size - 2.0, -size * 1.5 - 2.0), Vector2(size * 2.0 + 4.0, size * 1.62 + 4.0))


static func get_shadow_rect(size: float) -> Rect2:
	var extent: float = size * 0.85 + 1.0
	return Rect2(Vector2.ONE * -extent, Vector2.ONE * extent * 2.0)


static func get_body_texture(size: float, mucus: bool, body: Color, outline: Color) -> Texture2D:
	var key: Array = [size, mucus, body, outline]
	if _textures.has(key):
		return _textures[key] as Texture2D
	var image: Image = Image.new()
	var error: Error = image.load_svg_from_string(_make_svg(size, mucus, body, outline), RASTER_SCALE)
	assert(error == OK, "The shared slime body SVG must rasterize successfully.")
	var shadow_image: Image = Image.new()
	error = shadow_image.load_svg_from_string(_make_shadow_svg(size), RASTER_SCALE)
	assert(error == OK, "The shared slime shadow SVG must rasterize successfully.")
	var shadow_origin: Vector2i = Vector2i(0, image.get_height() + 2)
	var atlas_image: Image = Image.create_empty(
		maxi(image.get_width(), shadow_image.get_width()),
		shadow_origin.y + shadow_image.get_height(),
		false,
		Image.FORMAT_RGBA8
	)
	atlas_image.blit_rect(image, Rect2i(Vector2i.ZERO, image.get_size()), Vector2i.ZERO)
	atlas_image.blit_rect(shadow_image, Rect2i(Vector2i.ZERO, shadow_image.get_size()), shadow_origin)
	atlas_image.generate_mipmaps()
	var atlas: ImageTexture = ImageTexture.create_from_image(atlas_image)
	var body_texture: AtlasTexture = AtlasTexture.new()
	body_texture.atlas = atlas
	body_texture.region = Rect2(Vector2.ZERO, Vector2(image.get_size()))
	var shadow_texture: AtlasTexture = AtlasTexture.new()
	shadow_texture.atlas = atlas
	shadow_texture.region = Rect2(Vector2(shadow_origin), Vector2(shadow_image.get_size()))
	_textures[key] = body_texture
	_shadows[key] = shadow_texture
	return body_texture


static func get_shadow_texture(size: float, mucus: bool, body: Color, outline: Color) -> Texture2D:
	get_body_texture(size, mucus, body, outline)
	return _shadows[[size, mucus, body, outline]] as Texture2D


static func _make_shadow_svg(size: float) -> String:
	var bounds: Rect2 = get_shadow_rect(size)
	return (
		'<svg xmlns="http://www.w3.org/2000/svg" width="%.4f" height="%.4f" viewBox="%.4f %.4f %.4f %.4f">%s</svg>'
		% [
			bounds.size.x, bounds.size.y, bounds.position.x, bounds.position.y,
			bounds.size.x, bounds.size.y, _circle(Vector2.ZERO, size * 0.85, Color.WHITE)
		]
	)


static func _make_svg(size: float, mucus: bool, body: Color, outline: Color) -> String:
	var bounds: Rect2 = get_body_rect(size)
	var svg: String = (
		'<svg xmlns="http://www.w3.org/2000/svg" width="%.4f" height="%.4f" viewBox="%.4f %.4f %.4f %.4f">'
		% [bounds.size.x, bounds.size.y, bounds.position.x, bounds.position.y, bounds.size.x, bounds.size.y]
	)
	var points: PackedVector2Array = PackedVector2Array()
	for point: Vector2 in BODY_POINTS:
		points.append(point * size)
	svg += '<polygon points="%s" %s %s stroke-width="1.9" stroke-linejoin="miter"/>' % [
		_point_list(points), _color_attributes("fill", body), _color_attributes("stroke", outline)
	]
	if mucus:
		for spot: Vector2 in [Vector2(-0.6, -0.4), Vector2(0.6, -0.3), Vector2(0.2, -1.2)]:
			svg += _circle(spot * size, size * 0.13, Color("7293d9"))
	svg += _circle(Vector2(-0.33, -0.86) * size, size * 0.19, Color("fbfcf5"))
	svg += _circle(Vector2(0.33, -0.83) * size, size * 0.19, Color("fbfcf5"))
	svg += _circle(Vector2(-0.30, -0.83) * size, size * 0.085, outline)
	svg += _circle(Vector2(0.30, -0.80) * size, size * 0.085, outline)
	var mouth: PackedVector2Array = PackedVector2Array()
	for index: int in range(8):
		var angle: float = lerpf(0.12, PI - 0.12, float(index) / 7.0)
		mouth.append(Vector2(0.0, -size * 0.55) + Vector2.from_angle(angle) * size * 0.13)
	svg += _line(mouth, outline, 1.5)
	svg += _line(
		PackedVector2Array([Vector2(-0.53, -1.11) * size, Vector2(-0.30, -1.25) * size]),
		Color(1.0, 1.0, 0.97, 0.8),
		2.3
	)
	return svg + "</svg>"


static func _point_list(points: PackedVector2Array) -> String:
	var values: PackedStringArray = PackedStringArray()
	for point: Vector2 in points:
		values.append("%.4f,%.4f" % [point.x, point.y])
	return " ".join(values)


static func _color_attributes(property: String, color: Color) -> String:
	return '%s="#%s" %s-opacity="%.6f"' % [property, color.to_html(false), property, color.a]


static func _circle(center: Vector2, radius: float, color: Color) -> String:
	return '<circle cx="%.4f" cy="%.4f" r="%.4f" %s/>' % [
		center.x, center.y, radius, _color_attributes("fill", color)
	]


static func _line(points: PackedVector2Array, color: Color, width: float) -> String:
	return '<polyline points="%s" fill="none" %s stroke-width="%.4f" stroke-linejoin="miter"/>' % [
		_point_list(points), _color_attributes("stroke", color), width
	]
