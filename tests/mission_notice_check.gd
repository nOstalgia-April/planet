extends Node

const Notice = preload("res://scripts/ui/mission_notice.gd")
const BRIEFING: PackedScene = preload("res://scenes/ui/mission_briefing.tscn")
const RECEIPT: PackedScene = preload("res://scenes/ui/mission_receipt.tscn")

var _completed: int = 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute("res://artifacts/mission_note_20261017")
	get_tree().create_timer(30.0).timeout.connect(func() -> void: get_tree().quit(1))
	for scene: PackedScene in [BRIEFING, RECEIPT]:
		var notice: Notice = scene.instantiate() as Notice
		add_child(notice)
		notice.finished.connect(func() -> void: _completed += 1)
		notice.play()
		notice._animation.pause()
		assert(not notice._close.visible and notice._text.visible_characters == 0)
		notice.close()
		assert(notice.playing and _completed == 0, "Cannot dismiss unread text.")
		notice._animation.seek(0.65, true)
		notice._on_unrolled(&"unroll")
		notice.set_process(false)
		notice._process(0.1)
		assert(notice._text.visible_characters == 4, "45 characters per second.")
		assert(not notice._close.visible)
		assert(notice._typing_sound != null, "Typing the first clause plays Text_Typing.")
		# The fifth character of both notes is punctuation: the clause ends, but
		# the sound holds its minimum before stopping.
		notice._process(1.0 / notice.characters_per_second)
		assert(
			notice._typing_sound != null and not notice._typing_voiced,
			"A clause ending early keeps Text_Typing for its minimum."
		)
		await get_tree().create_timer(notice.min_typing_seconds + 0.1, true, false, true).timeout
		assert(notice._typing_sound == null, "Text_Typing stops once its minimum has passed.")
		notice._process(2.0 / notice.characters_per_second)
		assert(notice._typing_sound != null, "The next clause starts Text_Typing again.")
		await _click(Vector2(20, 20))
		assert(notice.phase == Notice.Phase.READING and notice._close.visible)
		assert(notice._typing_sound == null, "Revealing the whole note stops Text_Typing.")
		assert(_completed == 0, "A reveal click must not also dismiss.")
		await _click(Vector2(20, 20))
		assert(_completed == 0 and notice.playing, "Only the close action dismisses a read note.")
		for dimensions: Vector2i in [Vector2i(1920, 1080), Vector2i(1280, 800)]:
			get_window().size = dimensions
			await get_tree().process_frame
			await get_tree().process_frame
			assert(notice.get_global_rect().encloses(notice._page.get_global_rect()))
			assert(
				notice._text.get_content_height() <= notice._text.size.y, "All text fits on paper."
			)
			if "--capture" in OS.get_cmdline_user_args():
				await RenderingServer.frame_post_draw
				assert(
					(
						get_viewport().get_texture().get_image().save_png(
							(
								"res://artifacts/mission_note_20261017/%s_%d.png"
								% [notice.name, dimensions.x]
							)
						)
						== OK
					)
				)
		var hover: InputEventMouseMotion = InputEventMouseMotion.new()
		hover.position = notice._close.get_global_rect().get_center()
		get_tree().root.push_input(hover, true)
		await get_tree().process_frame
		await get_tree().process_frame
		if "--capture" in OS.get_cmdline_user_args():
			await RenderingServer.frame_post_draw
			assert((notice._close.get_node("Brush") as TextureRect).visible)
			get_viewport().get_texture().get_image().save_png(
				"res://artifacts/mission_note_20261017/%s_hover.png" % notice.name
			)
		await _click(notice._close.get_global_rect().get_center())
		await get_tree().create_timer(0.25).timeout
		assert(_completed == 1 and not notice.playing and not notice.visible)
		notice.play()
		notice.reveal_all()
		notice.close()
		notice.reset()
		await get_tree().create_timer(0.25).timeout
		assert(_completed == 1, "Reset cancels pending close callbacks.")
		notice.play()
		await get_tree().create_timer(notice.unroll_seconds + 0.1).timeout
		assert(notice.phase == Notice.Phase.TYPING)
		notice._process(20.0)
		assert(notice.phase == Notice.Phase.READING and notice._close.visible)
		notice.queue_free()
		await get_tree().process_frame
		_completed = 0
	print("PASS: both notes, typewriter, one-click reveal, gated close, layout and reset.")
	get_tree().quit()


func _click(point: Vector2) -> void:
	for pressed: bool in [true, false]:
		var event: InputEventMouseButton = InputEventMouseButton.new()
		event.position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		get_tree().root.push_input(event, true)
		await get_tree().process_frame
