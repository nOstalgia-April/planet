extends "res://scripts/场景动画/帧动画.gd"

enum SkinKind { DEFAULT, PINK, BLUE, RAINBOW }
enum Transition { STABLE, WIPING }

@export var default_frames: Array[Texture2D] = []
@export var pink_frames: Array[Texture2D] = []
@export var blue_frames: Array[Texture2D] = []
@export var rainbow_frames: Array[Texture2D] = []
@export_range(0.05, 2.0, 0.05) var transition_seconds: float = 0.45
@export var frame_index: int = 0:
	set(value):
		frame_index = value
		if is_node_ready():
			_sync_frame()

var current_skin: SkinKind = SkinKind.DEFAULT
var target_skin: SkinKind = SkinKind.DEFAULT
var requested_skin: SkinKind = SkinKind.DEFAULT
var transition: Transition = Transition.STABLE
var progress: float = 1.0

@onready var _sprite: Sprite2D = $贴图
@onready var _material: ShaderMaterial = _sprite.material as ShaderMaterial


func _ready() -> void:
	super._ready()
	assert(default_frames.size() == frame_count)
	assert(pink_frames.size() == frame_count)
	assert(blue_frames.size() == frame_count)
	assert(rainbow_frames.size() == frame_count)
	reset_skin()


func request_skin(skin: SkinKind) -> void:
	requested_skin = skin
	if transition == Transition.STABLE and current_skin != requested_skin:
		_begin_wipe()


func reset_skin() -> void:
	current_skin = SkinKind.DEFAULT
	target_skin = SkinKind.DEFAULT
	requested_skin = SkinKind.DEFAULT
	transition = Transition.STABLE
	progress = 1.0
	_sync_frame()


func _process(delta: float) -> void:
	if transition != Transition.WIPING:
		return
	progress = minf(1.0, progress + delta / transition_seconds)
	_material.set_shader_parameter("progress", progress)
	if progress < 1.0:
		return
	current_skin = target_skin
	transition = Transition.STABLE
	_sync_frame()
	if requested_skin != current_skin:
		_begin_wipe()


func _begin_wipe() -> void:
	target_skin = requested_skin
	transition = Transition.WIPING
	progress = 0.0
	_sync_frame()


func _sync_frame() -> void:
	_sprite.texture = _frames_for(current_skin)[frame_index]
	_material.set_shader_parameter("next_frame", _frames_for(target_skin)[frame_index])
	_material.set_shader_parameter("progress", progress)


func _frames_for(skin: SkinKind) -> Array[Texture2D]:
	match skin:
		SkinKind.PINK:
			return pink_frames
		SkinKind.BLUE:
			return blue_frames
		SkinKind.RAINBOW:
			return rainbow_frames
	return default_frames
