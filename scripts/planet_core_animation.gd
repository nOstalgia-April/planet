@tool
extends Node2D

const CoreClip = preload("res://scripts/planet_core_clip.gd")

## A music-clock-driven sequence. Only the current and next atlas stay cached.
@export var clip: CoreClip
@export var sprite: Sprite2D
@export_range(1.0, 60.0, 0.01) var frames_per_second: float = 30.0
@export var synchronize_music: bool = true
@export var music_event: String = "event:/Mx/Mx_GamePlay"
## Positive values advance the picture relative to the music.
@export_range(-180.0, 180.0, 0.01) var time_offset_seconds: float = 0.0
@export var loop_preview: bool = true

var current_frame: int = -1
var _preview_seconds: float = 0.0
var _wanted_page: int = 0
var _next_page: int = 0
var _pages: Dictionary[int, Texture2D] = {}
var _pending: Array[int] = []
var _shape_material: ShaderMaterial


func _ready() -> void:
	assert(clip != null and sprite != null, "Core animation requires its clip and sprite.")
	assert(not clip.page_paths.is_empty() and not clip.frame_tiles.is_empty())
	_shape_material = sprite.material as ShaderMaterial
	assert(_shape_material != null, "Core animation requires its radial shape material.")
	sprite.centered = false
	sprite.position = -clip.pivot
	sprite.region_enabled = true
	sprite.region_filter_clip_enabled = true
	_pages[0] = load(clip.page_paths[0]) as Texture2D
	seek_seconds(0.0)
	if Engine.is_editor_hint():
		set_process(false)
	elif synchronize_music:
		# Music continues while the tree is paused; the effect follows that same clock.
		process_mode = Node.PROCESS_MODE_ALWAYS


func _process(delta: float) -> void:
	_poll_pages()
	if synchronize_music:
		var seconds: float = GameAudio.get_music_position_seconds(music_event)
		if seconds >= 0.0:
			seek_seconds(seconds + time_offset_seconds)
	else:
		_preview_seconds += delta
		var duration: float = float(clip.frame_tiles.size()) / frames_per_second
		var seconds: float = (
			fposmod(_preview_seconds, duration) if loop_preview else _preview_seconds
		)
		seek_seconds(seconds)


## Seeking never waits for disk IO. A late page holds the last valid picture,
## then catches up to the music clock rather than slowing down the sequence.
func seek_seconds(seconds: float) -> void:
	var frame: int = clampi(
		int(floor(maxf(seconds, 0.0) * frames_per_second)), 0, clip.frame_tiles.size() - 1
	)
	var tile: int = clip.frame_tiles[frame]
	var per_page: int = clip.columns * clip.rows
	_wanted_page = tile / per_page
	_next_page = (_wanted_page + 1) % clip.page_paths.size()
	for page: int in _pages.keys():
		if page != _wanted_page and page != _next_page:
			_pages.erase(page)
	if _pages.has(_wanted_page):
		var local_tile: int = tile % per_page
		sprite.texture = _pages[_wanted_page]
		sprite.region_rect = Rect2(
			Vector2(local_tile % clip.columns, local_tile / clip.columns) * Vector2(clip.tile_size),
			Vector2(clip.tile_size)
		)
		var region: Rect2 = sprite.region_rect
		_shape_material.set_shader_parameter(
			"frame_region",
			Vector4(region.position.x, region.position.y, region.size.x, region.size.y)
		)
		current_frame = frame
	if not Engine.is_editor_hint():
		_request_page(_wanted_page)
		_request_page(_next_page)


func _request_page(page: int) -> void:
	if _pages.has(page) or page in _pending or _pending.size() >= 2:
		return
	var error: Error = ResourceLoader.load_threaded_request(clip.page_paths[page], "Texture2D")
	if error != OK:
		push_error("Unable to request core atlas: " + clip.page_paths[page])
		set_process(false)
		return
	_pending.append(page)


func _poll_pages() -> void:
	for page: int in _pending.duplicate():
		var status: ResourceLoader.ThreadLoadStatus = ResourceLoader.load_threaded_get_status(
			clip.page_paths[page]
		)
		if status == ResourceLoader.THREAD_LOAD_LOADED:
			var texture: Texture2D = (
				ResourceLoader.load_threaded_get(clip.page_paths[page]) as Texture2D
			)
			if page == _wanted_page or page == _next_page:
				_pages[page] = texture
			_pending.erase(page)
		elif (
			status == ResourceLoader.THREAD_LOAD_FAILED
			or status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE
		):
			_pending.erase(page)
			push_error("Unable to load core atlas: " + clip.page_paths[page])
			set_process(false)


func _exit_tree() -> void:
	# Every request must be retrieved, including prefetched pages on scene exit.
	for page: int in _pending:
		ResourceLoader.load_threaded_get(clip.page_paths[page])
	_pending.clear()
	_pages.clear()
