extends RefCounted

const GRID: Vector2i = Vector2i(560, 240)
const BOUNDS: Rect2 = Rect2(-0.78, -0.06, 1.56, 0.66)
const MAX_DRIPS: int = 3
const NEIGHBORS: Array[Vector2i] = [
	Vector2i(-1, 0),
	Vector2i(1, 0),
	Vector2i(0, -1),
	Vector2i(0, 1),
	Vector2i(-1, -1),
	Vector2i(1, -1),
	Vector2i(-1, 1),
	Vector2i(1, 1)
]

var pink_drips: PackedVector4Array
var blue_drips: PackedVector4Array
var _heap_indices: Array[int] = []
var _heap_costs: Array[float] = []
var _resistance: PackedFloat32Array
var _noise: FastNoiseLite = FastNoiseLite.new()


func build(
	seed_value: int,
	pink_source: Vector2,
	blue_source: Vector2,
	pink_size: float,
	blue_size: float,
	terrain: Image,
	center_uv: Vector2,
	radius_ratio: float
) -> Image:
	_noise.seed = seed_value
	_noise.frequency = 1.0
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.fractal_octaves = 1
	_resistance.resize(GRID.x * GRID.y)
	var texture_aspect: float = float(terrain.get_height()) / float(terrain.get_width())
	for y in range(GRID.y):
		for x in range(GRID.x):
			var point: Vector2 = _point(x, y)
			var texture_point: Vector2 = (
				center_uv + Vector2(-point.x, (1.0 - point.y) / texture_aspect) * radius_ratio
			)
			var texel: Vector2i = Vector2i(texture_point * Vector2(terrain.get_size()))
			texel = texel.clamp(Vector2i.ONE, terrain.get_size() - Vector2i(2, 2))
			var gray: float = terrain.get_pixelv(texel).r
			var crease: float = absf(gray - terrain.get_pixelv(texel + Vector2i(1, 0)).r)
			crease += absf(gray - terrain.get_pixelv(texel + Vector2i(0, 1)).r)
			var ridges: float = _noise.get_noise_2dv(point * 8.0) * 0.5 + 0.5
			_resistance[y * GRID.x + x] = 0.9 + ridges * ridges * 2.2 + crease * 1.3
	var pink_boundary: PackedFloat32Array = _make_boundary(pink_source, pink_size, seed_value + 31)
	var blue_boundary: PackedFloat32Array = _make_boundary(blue_source, blue_size, seed_value + 197)
	var pink: PackedFloat32Array = _solve(pink_source, pink_boundary)
	var blue: PackedFloat32Array = _solve(blue_source, blue_boundary)
	pink_drips = _find_drips(pink_boundary, pink_size)
	blue_drips = _find_drips(blue_boundary, blue_size)
	var result: Image = Image.create(GRID.x, GRID.y, false, Image.FORMAT_RGBAF)
	for y in range(GRID.y):
		for x in range(GRID.x):
			var index: int = y * GRID.x + x
			# RG = arrival time; BA = signed contour distance, negative inside.
			result.set_pixel(
				x, y, Color(pink[index], blue[index], pink_boundary[index], blue_boundary[index])
			)
	return result


func _make_boundary(source: Vector2, size: float, seed_value: int) -> PackedFloat32Array:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = seed_value
	var bend: float = rng.randf_range(-0.03, 0.03)
	var turn: float = rng.randf_range(-0.12, 0.12)
	var result: PackedFloat32Array
	result.resize(GRID.x * GRID.y)
	for y in range(GRID.y):
		for x in range(GRID.x):
			var point: Vector2 = _point(x, y)
			var p: Vector2 = ((point - source) / size).rotated(turn)
			p.x += sin(p.y * 13.0 + float(seed_value) * 0.17) * 0.024
			# Broad connected bends, with two scooped edges, follow the supplied pattern.
			var distance: float = _ellipse(p, Vector2(0.0, 0.105), Vector2(0.295, 0.20))
			distance = _smooth_min(
				distance, _ellipse(p, Vector2(-0.13, 0.23 + bend), Vector2(0.135, 0.10)), 0.055
			)
			distance = _smooth_min(
				distance, _ellipse(p, Vector2(0.235, 0.17), Vector2(0.125, 0.063)), 0.04
			)
			distance = _smooth_min(
				distance, _ellipse(p, Vector2(-0.265, 0.105), Vector2(0.09, 0.075)), 0.035
			)
			distance = -_smooth_min(
				-distance, _ellipse(p, Vector2(0.278, 0.064 + bend), Vector2(0.105, 0.064)), 0.022
			)
			distance = -_smooth_min(
				-distance, _ellipse(p, Vector2(0.265, 0.282), Vector2(0.135, 0.069)), 0.025
			)
			var radial: float = Vector2(point.x, 1.0 - point.y).length()
			result[y * GRID.x + x] = maxf(distance * size, radial - 1.003)
	return result


func _ellipse(point: Vector2, center: Vector2, radii: Vector2) -> float:
	return (((point - center) / radii).length() - 1.0) * minf(radii.x, radii.y)


func _smooth_min(first: float, second: float, width: float) -> float:
	var blend: float = clampf(0.5 + 0.5 * (second - first) / width, 0.0, 1.0)
	return lerpf(second, first, blend) - width * blend * (1.0 - blend)


func _solve(source: Vector2, boundary: PackedFloat32Array) -> PackedFloat32Array:
	var arrival: PackedFloat32Array
	arrival.resize(GRID.x * GRID.y)
	arrival.fill(INF)
	_heap_indices.clear()
	_heap_costs.clear()
	var cell: Vector2i = Vector2i(
		(source + Vector2(0.0, 0.016) - BOUNDS.position) / BOUNDS.size * Vector2(GRID)
	)
	cell = cell.clamp(Vector2i.ZERO, GRID - Vector2i.ONE)
	var source_index: int = cell.y * GRID.x + cell.x
	assert(boundary[source_index] < 0.012, "花朵源点必须位于色块内。")
	arrival[source_index] = 0.0
	_push(source_index, 0.0)
	var step_size: Vector2 = BOUNDS.size / Vector2(GRID)
	while not _heap_indices.is_empty():
		var cost: float = _heap_costs[0]
		var index: int = _pop()
		if cost > arrival[index] + 0.00001:
			continue
		cell = Vector2i(index % GRID.x, index / GRID.x)
		for offset in NEIGHBORS:
			var next: Vector2i = cell + offset
			if next.x < 0 or next.y < 0 or next.x >= GRID.x or next.y >= GRID.y:
				continue
			var next_index: int = next.y * GRID.x + next.x
			# Extend arrival data beyond the contour so bilinear filtering cannot
			# turn the final silhouette into a grid of square cells.
			if boundary[next_index] > 0.012:
				continue
			var drag: float = (_resistance[index] + _resistance[next_index]) * 0.5
			var direction_drag: float = 0.91 if offset.y > 0 else 1.08
			var next_cost: float = (
				cost + (Vector2(offset) * step_size).length() * drag * direction_drag
			)
			if next_cost < arrival[next_index]:
				arrival[next_index] = next_cost
				_push(next_index, next_cost)
	var maximum: float = 0.001
	for index in range(arrival.size()):
		if boundary[index] < 0.004 and is_finite(arrival[index]):
			maximum = maxf(maximum, arrival[index])
	for index in range(arrival.size()):
		arrival[index] = arrival[index] / maximum * 0.94 if is_finite(arrival[index]) else 2.0
	return arrival


func _find_drips(boundary: PackedFloat32Array, size: float) -> PackedVector4Array:
	var bottoms: PackedInt32Array
	var volumes: PackedFloat32Array
	bottoms.resize(GRID.x)
	bottoms.fill(-1)
	volumes.resize(GRID.x)
	var cell_height: float = BOUNDS.size.y / float(GRID.y)
	for x in range(GRID.x):
		for y in range(GRID.y):
			if boundary[y * GRID.x + x] < 0.0:
				bottoms[x] = y
				volumes[x] += cell_height
	var candidates: Array[Vector3] = []
	for x in range(12, GRID.x - 12):
		var bottom: int = bottoms[x]
		if bottom < 0 or volumes[x] < 0.10 * size:
			continue
		var tip: bool = true
		for neighbor in range(x - 10, x + 11):
			if bottoms[neighbor] > bottom:
				tip = false
				break
		if not tip:
			continue
		var reservoir: float = 0.0
		for neighbor in range(x - 8, x + 9):
			reservoir += volumes[neighbor] / 17.0
		# Downward protrusions with a broad reservoir above them are the only outlets.
		var prominence: float = maxf(
			0.0, float(bottom - maxi(bottoms[x - 12], bottoms[x + 12])) * cell_height
		)
		candidates.append(Vector3(float(x), float(bottom), reservoir + prominence * 2.0))
	candidates.sort_custom(_larger_reservoir)
	var drips: PackedVector4Array
	drips.resize(MAX_DRIPS)
	var count: int = 0
	for candidate in candidates:
		var point: Vector2 = _point(int(candidate.x), int(candidate.y))
		var separate: bool = true
		for index in range(count):
			if absf(point.x - drips[index].x) < 0.14 * size:
				separate = false
		if not separate:
			continue
		var volume: float = clampf(candidate.z / (0.42 * size), 0.0, 1.0)
		var width: float = lerpf(0.006, 0.010, volume) * size
		var length: float = lerpf(0.045, 0.083, volume) * size
		drips[count] = Vector4(point.x, point.y - 0.006 * size, width, length)
		count += 1
		if count == MAX_DRIPS:
			break
	return drips


func _larger_reservoir(first: Vector3, second: Vector3) -> bool:
	return first.z > second.z


func _point(x: int, y: int) -> Vector2:
	return BOUNDS.position + (Vector2(x, y) + Vector2.ONE * 0.5) / Vector2(GRID) * BOUNDS.size


func _push(index: int, cost: float) -> void:
	var position: int = _heap_indices.size()
	_heap_indices.append(index)
	_heap_costs.append(cost)
	while position > 0:
		var parent: int = (position - 1) / 2
		if _heap_costs[parent] <= cost:
			break
		_heap_indices[position] = _heap_indices[parent]
		_heap_costs[position] = _heap_costs[parent]
		position = parent
	_heap_indices[position] = index
	_heap_costs[position] = cost


func _pop() -> int:
	var result: int = _heap_indices[0]
	var last_index: int = _heap_indices.pop_back()
	var last_cost: float = _heap_costs.pop_back()
	if _heap_indices.is_empty():
		return result
	var position: int = 0
	while position * 2 + 1 < _heap_indices.size():
		var child: int = position * 2 + 1
		if child + 1 < _heap_indices.size() and _heap_costs[child + 1] < _heap_costs[child]:
			child += 1
		if last_cost <= _heap_costs[child]:
			break
		_heap_indices[position] = _heap_indices[child]
		_heap_costs[position] = _heap_costs[child]
		position = child
	_heap_indices[position] = last_index
	_heap_costs[position] = last_cost
	return result
