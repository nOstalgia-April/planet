extends RefCounted

# The screenshot's circular bodies measure about 52 and 119 px against a 556 px globe.
# Diameter/globe diameter equals radius/globe radius. Transparent padding and
# the pointer are excluded; they must not influence density or collision sizes.
const REFERENCE_MINIMUM_RATIO: float = 52.0 / 556.0
const REFERENCE_MAXIMUM_RATIO: float = 119.0 / 556.0
const SECTORS: int = 48
const POINTER_REACH: float = 125.0 / 97.0

var minimum_ratio: float = REFERENCE_MINIMUM_RATIO
var maximum_ratio: float = REFERENCE_MAXIMUM_RATIO
var population_at_maximum: int = 48
var maximum_cluster_span: float = deg_to_rad(30.0)


class Cluster:
	extends RefCounted

	var species: int = 0
	var count: int = 0
	var position_sum: Vector2 = Vector2.ZERO
	var sectors: int = 0
	var angle: float = 0.0
	var lower: float = 0.0
	var upper: float = 0.0
	var radius_ratio: float = 0.0


func radius_for_count(count: int) -> float:
	if count <= 0:
		return 0.0
	var density: float = clampf(float(count - 1) / float(population_at_maximum - 1), 0.0, 1.0)
	return sqrt(lerpf(minimum_ratio * minimum_ratio, maximum_ratio * maximum_ratio, density))


func build(
	positions: PackedVector2Array,
	kinds: PackedInt32Array,
	previous: Array[Cluster],
	populations: PackedInt32Array = PackedInt32Array()
) -> Array[Cluster]:
	assert(positions.size() == kinds.size())
	assert(populations.is_empty() or populations.size() == positions.size())
	var seeds: Dictionary[int, Cluster] = {}
	var sector_width: float = TAU / float(SECTORS)
	for index: int in range(positions.size()):
		var angle: float = fposmod(positions[index].angle(), TAU)
		var sector: int = int(floor(angle / sector_width)) % SECTORS
		var key: int = kinds[index] * SECTORS + sector
		if not seeds.has(key):
			var seed: Cluster = Cluster.new()
			seed.species = kinds[index]
			seed.angle = (float(sector) + 0.5) * sector_width
			seed.lower = -sector_width * 0.5
			seed.upper = sector_width * 0.5
			seed.sectors = 1 << sector
			seeds[key] = seed
		var population: int = populations[index] if not populations.is_empty() else 1
		assert(population > 0)
		seeds[key].count += population
		seeds[key].position_sum += positions[index] * float(population)
	var keys: Array[int] = seeds.keys()
	keys.sort()
	var clusters: Array[Cluster] = []
	for key: int in keys:
		var seed: Cluster = seeds[key]
		var shift: float = angle_difference(seed.angle, seed.position_sum.angle())
		seed.angle += shift
		seed.lower -= shift
		seed.upper -= shift
		seed.radius_ratio = radius_for_count(seed.count)
		clusters.append(seed)
	# Merge before any screen-space repulsion. A bounded geographical span stops
	# connected chains from accumulating into a false planet-wide marker.
	while _merge_closest_overlap(clusters, previous):
		pass
	return clusters


func _merge_closest_overlap(clusters: Array[Cluster], previous: Array[Cluster]) -> bool:
	var best_pair: Vector2i = Vector2i(-1, -1)
	var best_overlap: float = 0.0
	for first: int in range(clusters.size()):
		var a: Cluster = clusters[first]
		for second: int in range(first + 1, clusters.size()):
			var b: Cluster = clusters[second]
			if a.species != b.species:
				continue
			var delta: float = angle_difference(a.angle, b.angle)
			var lower: float = minf(a.lower, delta + b.lower)
			var upper: float = maxf(a.upper, delta + b.upper)
			if upper - lower > maximum_cluster_span + 0.0001:
				continue
			var margin: float = 0.008
			for old: Cluster in previous:
				if old.species == a.species and old.sectors & a.sectors and old.sectors & b.sectors:
					margin = 0.035
					break
			var a_center: Vector2 = (
				Vector2.from_angle(a.angle) * (1.0 + POINTER_REACH * a.radius_ratio)
			)
			var b_center: Vector2 = (
				Vector2.from_angle(b.angle) * (1.0 + POINTER_REACH * b.radius_ratio)
			)
			var overlap: float = (
				a.radius_ratio + b.radius_ratio + margin - a_center.distance_to(b_center)
			)
			if overlap > best_overlap:
				best_overlap = overlap
				best_pair = Vector2i(first, second)
	if best_pair.x < 0:
		return false
	var a: Cluster = clusters[best_pair.x]
	var b: Cluster = clusters[best_pair.y]
	var delta: float = angle_difference(a.angle, b.angle)
	var lower: float = minf(a.lower, delta + b.lower)
	var upper: float = maxf(a.upper, delta + b.upper)
	a.position_sum += b.position_sum
	a.count += b.count
	a.sectors |= b.sectors
	var shift: float = angle_difference(a.angle, a.position_sum.angle())
	a.angle += shift
	a.lower = lower - shift
	a.upper = upper - shift
	a.radius_ratio = radius_for_count(a.count)
	clusters.remove_at(best_pair.y)
	return true
