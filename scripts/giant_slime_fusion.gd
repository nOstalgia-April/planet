extends RefCounted


class Plan:
	extends RefCounted
	var actors: Array[PrototypeSlime] = []
	var contributions: Dictionary[int, int] = {}
	var owner_id: int = -1
	var value_units: int = 0


class Source:
	extends RefCounted
	var nest: NestState
	var actors: Array[PrototypeSlime] = []


# The caller has already excluded visible, airborne and captured individuals.
# Every pair in a group must overlap; chains cannot fuse distant regions.
static func plan_batches(
	run: PrototypeRun, candidates: Array[PrototypeSlime], activity_radius: float
) -> Array[Plan]:
	var plans: Array[Plan] = []
	if not run.giant_unlocked:
		return plans
	var sources: Array[Source] = []
	for nest: NestState in run.nests:
		var source: Source = Source.new()
		source.nest = nest
		for actor: PrototypeSlime in candidates:
			if actor.nest_id == nest.nest_id and actor.can_fuse():
				source.actors.append(actor)
		if not source.actors.is_empty():
			sources.append(source)
	while not sources.is_empty():
		sources.sort_custom(_most_contributors_first)
		var group: Array[Source] = _find_group(
			sources, activity_radius, run.settings.giant_fusion_threshold
		)
		if group.is_empty():
			break
		var plan: Plan = Plan.new()
		var remaining: int = run.settings.giant_fusion_threshold
		for source: Source in group:
			var count: int = mini(source.actors.size(), remaining)
			if plan.owner_id < 0:
				plan.owner_id = source.nest.nest_id
			plan.contributions[source.nest.nest_id] = count
			for _index: int in range(count):
				var actor: PrototypeSlime = source.actors.pop_back()
				plan.actors.append(actor)
				plan.value_units += run.get_capture_value_units(
					actor.species as NestState.Species, actor.high_value
				)
			remaining -= count
			if source.actors.is_empty():
				sources.erase(source)
			if remaining == 0:
				break
		plans.append(plan)
	return plans


static func _most_contributors_first(a: Source, b: Source) -> bool:
	if a.actors.size() == b.actors.size():
		return a.nest.nest_id < b.nest.nest_id
	return a.actors.size() > b.actors.size()


static func _find_group(sources: Array[Source], radius: float, threshold: int) -> Array[Source]:
	for anchor: Source in sources:
		var group: Array[Source] = [anchor]
		var count: int = anchor.actors.size()
		if count >= threshold:
			return group
		for source: Source in sources:
			if source == anchor:
				continue
			var overlaps: bool = true
			for member: Source in group:
				if source.nest.position.distance_to(member.nest.position) > radius * 2.0:
					overlaps = false
					break
			if not overlaps:
				continue
			group.append(source)
			count += source.actors.size()
			if count >= threshold:
				group.sort_custom(_most_contributors_first)
				return group
	return []
