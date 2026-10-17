extends Node

const Notice = preload("res://scripts/ui/mission_notice.gd")
const BRIEFING: PackedScene = preload("res://scenes/ui/mission_briefing.tscn")
const RECEIPT: PackedScene = preload("res://scenes/ui/mission_receipt.tscn")

var _completed: int = 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	for scene: PackedScene in [BRIEFING, RECEIPT]:
		var notice: Notice = scene.instantiate() as Notice
		add_child(notice)
		notice.finished.connect(func() -> void: _completed += 1)
		notice.play()
		notice._sequence.pause()
		await get_tree().process_frame
		assert(notice._sections.size() == 3)
		assert(notice._black.color == Color.BLACK)
		assert(is_equal_approx(notice.final_hold_seconds, 3.0))
		notice._sequence.custom_step(notice.transition_seconds + notice.reveal_seconds)
		assert(is_equal_approx(notice._sections[0].modulate.a, 1.0))
		assert(is_zero_approx(notice._sections[1].modulate.a))
		for code: Key in [KEY_ESCAPE, KEY_SPACE, KEY_ENTER]:
			var event: InputEventKey = InputEventKey.new()
			event.keycode = code
			event.pressed = true
			get_viewport().push_input(event)
			assert(get_viewport().is_input_handled(), "Notice consumes keyboard input.")
		var click: InputEventMouseButton = InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = true
		get_viewport().push_input(click)
		assert(get_viewport().is_input_handled(), "Notice consumes mouse input.")
		assert(is_zero_approx(notice._sections[1].modulate.a))
		assert(_completed == 0)
		notice._sequence.custom_step(notice.section_hold_seconds + notice.reveal_seconds)
		assert(is_equal_approx(notice._sections[1].modulate.a, 1.0))
		assert(is_zero_approx(notice._sections[2].modulate.a))
		notice._sequence.custom_step(notice.section_hold_seconds + notice.reveal_seconds)
		assert(is_equal_approx(notice._sections[2].modulate.a, 1.0))
		for dimensions: Vector2i in [Vector2i(1920, 1080), Vector2i(1280, 800)]:
			get_window().size = dimensions
			await get_tree().process_frame
			await get_tree().process_frame
			var page_rect: Rect2 = notice._page.get_global_rect()
			assert(
				notice.get_global_rect().encloses(page_rect),
				"%s / %s" % [notice.get_global_rect(), page_rect]
			)
			for section: Control in notice._sections:
				assert(page_rect.encloses(section.get_global_rect()))
			if "--capture" in OS.get_cmdline_user_args():
				await RenderingServer.frame_post_draw
				var path: String = (
					"res://artifacts/mission_notice_task/%s_%d.png" % [notice.name, dimensions.x]
				)
				assert(get_viewport().get_texture().get_image().save_png(path) == OK)
		notice._sequence.custom_step(2.99)
		assert(_completed == 0 and is_equal_approx(notice._page.modulate.a, 1.0))
		notice._sequence.custom_step(0.02)
		assert(_completed == 0)
		notice._sequence.custom_step(notice.transition_seconds)
		assert(_completed == 1)
		notice.reset()
		assert(not notice.visible and not notice.playing)
		notice.play()
		notice.reset()
		await get_tree().process_frame
		assert(_completed == 1)
		notice.queue_free()
		await get_tree().process_frame
		_completed = 0
	print("PASS: both notices, three reveals, blocked input, full 3-second hold, layout and reset.")
	get_tree().quit()
