extends Control

@export var forms: Array[SpriteFrames] = []
@export var resting_bounds: Array[Rect2] = []
@export var display_heights: PackedFloat32Array = PackedFloat32Array([340.0, 280.0, 150.0])
@export var edge_margin: Vector2 = Vector2(48.0, 42.0)
@export_range(0.1, 2.0, 0.05) var fallback_slide_seconds: float = 0.75

var selected_form: int = 0
var elapsed: float = 0.0
var paused: bool = false
var playback_speed: float = 1.0

@onready var sprite: AnimatedSprite2D = $Sprite


func _ready() -> void:
	assert(forms.size() == 3 and resting_bounds.size() == 3)
	select_form(0)


func _process(delta: float) -> void:
	if not paused:
		seek(elapsed + delta * playback_speed)


func select_form(index: int) -> void:
	assert(index >= 0 and index < forms.size())
	selected_form = index
	sprite.sprite_frames = forms[index]
	paused = false
	seek(0.0)


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
