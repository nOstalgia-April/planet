extends Node

const Shine = preload("res://scripts/effects/jewelry_shine.gd")
const ItemArt = preload("res://scripts/物品动画/动画物件.gd")
const Drill = preload("res://scripts/drill_monster.gd")
const SLIME: PackedScene = preload("res://scenes/world/slime.tscn")
const MOLE: PackedScene = preload("res://scenes/world/drill_monster.tscn")

var _failures: Array[String] = []
var _actors: Array[PrototypeSlime] = []
var _effects: Array[Shine] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()


func _run() -> void:
	var surface: PlanetSurface = PlanetSurface.new()
	add_child(surface)
	for kind: int in range(3):
		for copy_index: int in range(2):
			var packed: PackedScene = MOLE if kind == 2 else SLIME
			var actor: PrototypeSlime = packed.instantiate() as PrototypeSlime
			actor.process_mode = Node.PROCESS_MODE_PAUSABLE
			add_child(actor)
			actor.setup(kind + 1, Vector2.UP * 240.0, surface)
			actor.set_process(false)
			var ordinary: ItemArt = (actor as Drill).art if kind == 2 else actor.slime_art._active
			_check(not ordinary.has_node("JewelryShine"), "ordinary art has no jewelry effect")
			actor.configure_species(kind as PrototypeSlime.Species, true, 6)
			var art: ItemArt = (actor as Drill).art if kind == 2 else actor.slime_art._active
			art.play_clip(&"待机")
			art.animation_player.pause()
			var effect: Shine = art.get_node("JewelryShine") as Shine
			_check(effect.is_processing(), "selected valuable art activates its own effect")
			_check(effect._has_jewelry, "all three valuable idle clips contain jewelry")
			_check(effect.shine_seconds == 0.6, "approved shine duration")
			_check(effect.cooldown_seconds == 2.0, "two-second cooldown")
			_check(effect.random_wait_seconds == Vector2(0.5, 3.0), "approved random wait range")
			_check_frames(art, effect)
			art.show_frame(&"待机", 0)
			effect.set_process(false)
			_actors.append(actor)
			_effects.append(effect)
	for first: int in _effects.size():
		for second: int in range(first + 1, _effects.size()):
			_check(
				_effects[first]._material != _effects[second]._material,
				"materials are per individual"
			)
			_check(
				_effects[first]._random != _effects[second]._random,
				"random streams are per individual"
			)
	_check_timing()
	await _check_lifecycle()
	for actor: PrototypeSlime in _actors:
		actor.queue_free()
	await get_tree().process_frame
	for failure: String in _failures:
		push_error(failure)
	print(
		(
			"PASS: jewelry frame bindings, six independent clocks, cooldowns, visibility and pause"
			if _failures.is_empty()
			else "FAIL: jewelry shine"
		)
	)
	get_tree().quit(0 if _failures.is_empty() else 1)


func _check_frames(art: ItemArt, effect: Shine) -> void:
	for clip: StringName in art.animation_order:
		for frame: int in art.get_frame_count(clip):
			art.show_frame(clip, frame)
			var source: Texture2D = effect.target.texture
			if not effect.frames.masks.has(source):
				_check(not effect.is_processing(), "dirt-only frames suspend the effect")
				_check(
					float(effect._material.get_shader_parameter("phase")) < 0.0, "no light on dirt"
				)
				continue
			var mask: Texture2D = effect.frames.masks[source]
			var region: Rect2 = effect.frames.regions[source]
			_check(mask.get_size() == region.size, "cropped mask matches its source region")
			_check(
				effect._material.get_shader_parameter("jewelry_mask") == mask,
				"texture changes immediately select the correct mask"
			)
			_check(
				effect._material.get_shader_parameter("texture_size") == source.get_size(),
				"suction and dive canvas sizes stay aligned"
			)


func _check_timing() -> void:
	var starts: Array[PackedFloat64Array] = []
	var last_end: PackedFloat64Array = PackedFloat64Array()
	var last_start: PackedFloat64Array = PackedFloat64Array()
	for effect: Shine in _effects:
		starts.append(PackedFloat64Array())
		last_end.append(-1.0)
		last_start.append(-1.0)
		effect._shine_elapsed = -1.0
		effect._wait_remaining = effect._random_wait()
	var step: float = 1.0 / 60.0
	for tick: int in range(1, 3601):
		var now: float = tick * step
		for index: int in _effects.size():
			var effect: Shine = _effects[index]
			var was_shining: bool = effect._shine_elapsed >= 0.0
			effect._process(step)
			var shining: bool = effect._shine_elapsed >= 0.0
			if shining and not was_shining:
				starts[index].append(now)
				last_start[index] = now
				if last_end[index] < 0.0:
					_check(now >= 0.5 and now <= 3.02, "first shine waits 0.5-3 seconds")
				else:
					var wait: float = now - last_end[index]
					_check(
						wait >= 2.5 - 0.001 and wait <= 5.02,
						"shine end is followed by cooldown plus random wait"
					)
			elif was_shining and not shining:
				_check(
					absf(now - last_start[index] - 0.6) < 0.02,
					"sweep lasts the approved 0.6 seconds"
				)
				last_end[index] = now
	for index: int in starts.size():
		_check(starts[index].size() >= 10, "each individual repeatedly triggers")
		if index > 0:
			_check(
				starts[index] != starts[index - 1],
				"neighboring individuals do not share a schedule"
			)


func _check_lifecycle() -> void:
	var effect: Shine = _effects[0]
	effect._wait_remaining = 0.0
	effect._shine_elapsed = -1.0
	effect._process(0.1)
	effect._process(0.2)
	_actors[0].hide()
	_check(
		not effect.is_processing() and effect._shine_elapsed < 0.0, "hiding cancels a partial sweep"
	)
	_check(effect._wait_remaining >= 2.5, "cancelled sweep cannot immediately flash again")
	_actors[0].show()
	_check(effect.is_processing(), "showing restores the independent clock")
	var wait: float = effect._wait_remaining
	effect.animation_player.speed_scale = 0.0
	effect._process(10.0)
	_check(effect._wait_remaining == wait, "local tutorial freeze suspends the effect")
	effect.animation_player.speed_scale = 1.0
	get_tree().paused = true
	await get_tree().process_frame
	await get_tree().process_frame
	_check(effect._wait_remaining == wait, "tree pause freezes the effect")
	get_tree().paused = false
	var mole: Drill = _actors[4] as Drill
	var mole_effect: Shine = _effects[4]
	mole_effect._wait_remaining = 0.0
	mole_effect._shine_elapsed = -1.0
	mole_effect._process(0.1)
	mole.art.show_frame(&"鼓包", 0)
	_check(not mole_effect.is_processing(), "underground mole suspends its shine")
	_check(
		float(mole_effect._material.get_shader_parameter("phase")) < 0.0,
		"underground frame clears any old shine"
	)
	mole.art.show_frame(&"夹夹", 0)
	_check(mole_effect.is_processing(), "exposed mole resumes its own clock")
	mole.art.set_suction(true)
	_check(mole_effect._has_jewelry, "mole suction retains its jewelry mask")
	mole.configure_species(PrototypeSlime.Species.DRILL, false, 2)
	_check(not mole_effect.is_processing(), "ordinary variant leaves valuable effect dormant")


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
