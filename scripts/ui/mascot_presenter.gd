extends Control

signal entrance_finished

@export var forms: Array[SpriteFrames] = []
@export var resting_bounds: Array[Rect2] = []
@export var display_heights: PackedFloat32Array = PackedFloat32Array([340.0, 280.0, 150.0])
@export var edge_margin: Vector2 = Vector2(48.0, 42.0)
@export var ignore_time_scale: bool = false
@export_range(0.1, 2.0, 0.05) var fallback_slide_seconds: float = 0.75

var selected_form: int = 0
var elapsed: float = 0.0
var paused: bool = false
var playback_speed: float = 1.0
var speaking: bool = false
var speaking_elapsed: float = 0.0

var _speaking_started_at: float = 0.0
var _entrance_finished_emitted: bool = false

@onready var sprite: AnimatedSprite2D = $Sprite


func _ready() -> void:
	assert(forms.size() == 3 and resting_bounds.size() == 3)
	select_form(0)


func _process(delta: float) -> void:
	if paused:
		return
	if ignore_time_scale:
		delta /= Engine.time_scale
	var was_entering: bool = elapsed < entrance_duration()
	seek(elapsed + delta * playback_speed)
	if was_entering and elapsed >= entrance_duration() and not _entrance_finished_emitted:
		_entrance_finished_emitted = true
		entrance_finished.emit()


func select_form(index: int) -> void:
	assert(index >= 0 and index < forms.size())
	selected_form = index
	sprite.sprite_frames = forms[index]
	paused = false
	speaking = false
	speaking_elapsed = 0.0
	_speaking_started_at = 0.0
	_entrance_finished_emitted = false
	seek(0.0)


func set_speaking(enabled: bool) -> void:
	if enabled:
		assert(forms[selected_form].has_animation(&"talk"))
	if speaking == enabled:
		return
	speaking = enabled
	speaking_elapsed = 0.0
	_speaking_started_at = maxf(elapsed, entrance_duration())
	seek(elapsed)


func entrance_duration() -> float:
	var frames: SpriteFrames = forms[selected_form]
	if not frames.has_animation(&"enter"):
		return fallback_slide_seconds
	return frames.get_frame_count(&"enter") / frames.get_animation_speed(&"enter")


func seek(seconds: float) -> void:
	elapsed = maxf(seconds, 0.0)
	var frames: SpriteFrames = forms[selected_form]
	var entry_seconds: float = entrance_duration()
	var entering: bool = elapsed < entry_seconds
	var has_entry: bool = frames.has_animation(&"enter")
	var clip: StringName = &"enter" if entering and has_entry else &"idle"
	var clip_seconds: float = elapsed if entering else elapsed - entry_seconds
	if speaking:
		speaking_elapsed = maxf(elapsed - _speaking_started_at, 0.0)
		if not entering:
			clip = &"talk"
			clip_seconds = speaking_elapsed
	var frame_index: int = floori(clip_seconds * frames.get_animation_speed(clip))
	var count: int = frames.get_frame_count(clip)
	sprite.animation = clip
	sprite.frame = mini(frame_index, count - 1) if clip == &"enter" else frame_index % count
	# Preserve the complete source canvas: its transparent space contains the entrance motion.
	var bounds: Rect2 = resting_bounds[selected_form]
	var factor: float = display_heights[selected_form] / bounds.size.y
	sprite.scale = Vector2.ONE * factor
	sprite.position = -edge_margin - bounds.end * factor
	if entering and not has_entry:
		var progress: float = elapsed / entry_seconds
		var distance: float = edge_margin.x + bounds.size.x * factor + 12.0
		sprite.position.x += distance * pow(1.0 - progress, 3.0)
