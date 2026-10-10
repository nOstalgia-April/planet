extends Node2D

@export var candy_scene: PackedScene
@export_range(4, 30, 1) var bursts_per_harvest: int = 14
@export_range(1, 4, 1) var candies_per_burst: int = 2
@export_range(0.0, 160.0, 2.0) var spray_width: float = 90.0
@export_range(0.2, 1.5, 0.05) var flight_seconds: float = 0.65
@export_range(0.4, 2.0, 0.05) var candy_size: float = 1.2

var emitted_bursts: int = 0
var _finished: bool = false
var _preview_mode: bool = false
var _preview_elapsed: float = 0.0


func _ready() -> void:
	assert(candy_scene != null, "The harvest stream requires its candy scene.")
	_preview_mode = get_tree().current_scene == self
	set_process(_preview_mode)


# Progress drives presentation only. The run still settles one completed harvest.
func update_capture(origin: Vector2, destination: Vector2, progress: float) -> void:
	if _finished:
		return
	var target_bursts: int = int(floor(clampf(progress, 0.0, 1.0) * bursts_per_harvest))
	while emitted_bursts < target_bursts:
		for index: int in range(candies_per_burst):
			var candy: CollectionEffect = candy_scene.instantiate() as CollectionEffect
			add_child(candy)
			candy.duration = flight_seconds
			candy.size = candy_size
			var phase: float = float(emitted_bursts * candies_per_burst + index) * 2.399963
			var spray: Vector2 = Vector2(cos(phase), -absf(sin(phase))) * spray_width
			candy.play(origin, destination, 0, spray)
		emitted_bursts += 1


func finish() -> void:
	_finished = true
	set_process(true)


func _process(delta: float) -> void:
	if _preview_mode:
		_preview_elapsed += delta
		var center: Vector2 = get_viewport_rect().size * 0.5
		update_capture(center + Vector2(130, 80), center + Vector2(-170, -100), _preview_elapsed)
		if _preview_elapsed >= 2.0:
			_preview_elapsed = 0.0
			emitted_bursts = 0
	elif _finished and get_child_count() == 0:
		queue_free()
