extends Node

const GameScene: PackedScene = preload("res://scenes/game.tscn")
const Game = preload("res://features/tutorial_intro/story_game.gd")
const Flow = preload("res://features/tutorial_intro/story_flow.gd")
const Dialogue = preload("res://scripts/ui/mascot_dialogue.gd")
const Drill = preload("res://scripts/drill_monster.gd")

var _game: Game
var _flow: Flow
var _failures: Array[String] = []
var _started: Array[int] = []
var _output: String = "res://artifacts/story_flow_check_%d" % Time.get_unix_time_from_system()


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	get_tree().create_timer(180.0, true, false, true).timeout.connect(_timeout)
	_game = GameScene.instantiate() as Game
	get_tree().root.add_child(_game)
	get_tree().current_scene = _game
	_flow = _game.story
	_check(not _game.has_node("PreviewNavigation"), "formal gameplay has no preview shortcuts")
	_check(
		GameAudio.has_events(_flow.talk_events), "all three mascot voice events exist in the Bank"
	)
	_flow.story_started.connect(func(kind: int) -> void: _started.append(kind))
	var whooshes: Array[int] = [0]
	_flow.narrative.entered.connect(func() -> void: whooshes[0] += 1)
	_flow.narrative.exited.connect(func() -> void: whooshes[0] += 1)
	await _close_note(_flow.briefing)
	await _wait_talk(Flow.Kind.OPENING)
	_check(whooshes[0] == 1, "the mascot's entrance whooshes once")
	_check(GameAudio._music_menu_held, "the mascot on screen holds Music_Menu at 1")
	_check(_flow._voice != null, "opening typing starts the cloak voice")
	_check(
		_flow.narrative.lines.size() == 3, "opening contains only the three approved story lines"
	)
	_check(
		not get_tree().paused and is_equal_approx(Engine.time_scale, 0.5),
		"dialogue leaves the background running at half speed"
	)
	var candy: int = _game.run.candy
	var clock: float = _game.run.nests[0].spawn_clock
	var speaker_clock: float = _flow.active_dialogue.presenter.elapsed
	var background: AnimationPlayer = (
		_game.get_node("美术背景/地壳裁剪/画布/近景背景/星星/动画播放器") as AnimationPlayer
	)
	var background_clock: float = background.current_animation_position
	var background_length: float = background.current_animation_length
	var monster: PrototypeSlime = _game._slimes[0]
	var monster_clock: float = monster._elapsed
	var monster_animation: AnimationPlayer = monster.slime_art._active.animation_player
	var monster_animation_clock: float = monster_animation.current_animation_position
	var monster_animation_length: float = monster_animation.current_animation_length
	var drill: Drill = _game.drill_scene.instantiate() as Drill
	_game.add_child(drill)
	drill.setup(monster.nest_id, monster.position, monster.surface)
	drill.launch(Vector2.UP)
	drill.set_simulation_speed(monster.simulation_speed)
	var drill_clock: float = drill.phase_remaining
	var drill_animation_clock: float = drill.art.animation_player.current_animation_position
	var before: int = Time.get_ticks_msec()
	await get_tree().create_timer(0.8, true, false, true).timeout
	var real_seconds: float = float(Time.get_ticks_msec() - before) / 1000.0
	_check(
		absf(monster._elapsed - monster_clock - real_seconds * 0.1) < 0.025,
		"monster movement clock advances at ten percent real time"
	)
	_check(
		(
			absf(
				(
					fposmod(
						monster_animation.current_animation_position - monster_animation_clock,
						monster_animation_length
					)
					- real_seconds * 0.1
				)
			)
			< 0.025
		),
		"monster animation advances at ten percent real time"
	)
	_check(
		absf(drill_clock - drill.phase_remaining - real_seconds * 0.1) < 0.025,
		"drill movement clock advances at ten percent real time"
	)
	_check(
		(
			absf(
				(
					drill.art.animation_player.current_animation_position
					- drill_animation_clock
					- real_seconds * 0.1
				)
			)
			< 0.025
		),
		"drill animation advances at ten percent real time"
	)
	drill.queue_free()
	_check(
		(
			absf(
				(
					fposmod(
						background.current_animation_position - background_clock, background_length
					)
					- real_seconds * 0.5
				)
			)
			< 0.08
		),
		"background animation advances at half real time"
	)
	_check(
		absf(_flow.active_dialogue.presenter.elapsed - speaker_clock - real_seconds) < 0.12,
		"NPC animation uses real time while the world is slowed"
	)
	_check(
		_game.run.candy == candy and is_equal_approx(_game.run.nests[0].spawn_clock, clock),
		"reading dialogue does not advance economy or spawn clocks"
	)
	await _key(KEY_ESCAPE)
	_check(get_tree().paused, "Escape pauses formal gameplay during dialogue")
	speaker_clock = _flow.active_dialogue.presenter.elapsed
	await get_tree().create_timer(0.15, true, false, true).timeout
	_check(
		is_equal_approx(_flow.active_dialogue.presenter.elapsed, speaker_clock),
		"manual pause still freezes the NPC"
	)
	await _key(KEY_ESCAPE)
	_check(not get_tree().paused, "Escape resumes the paused dialogue")
	var click_sound: FmodEventDescription = FmodServer.get_event(
		GameAudio.resolve_event_path(_flow.click_event)
	)
	var clicks: int = click_sound.get_instance_count()
	await _click()
	_check(
		(
			_flow.active_dialogue.phase == Dialogue.Phase.HOLDING
			and _flow.active_dialogue.line_index == 0
		),
		"first actual click reveals the line without advancing"
	)
	_check(click_sound.get_instance_count() > clicks, "clicking the dialogue plays Gibber_Click")
	await _capture("opening")
	await _finish_dialogue()
	await _wait_idle()
	_check(_flow._voice == null, "finishing the opening releases its voice")
	_check(whooshes[0] == 2, "the mascot leaving whooshes once")
	_check(not GameAudio._music_menu_held, "the mascot leaving releases Music_Menu")
	var before_shortcut: int = _game.run.candy
	await _key(KEY_N)
	_check(
		_game.run.candy == before_shortcut and _game.run.get_technology_level("cultivation") == 0,
		"preview next-beat key cannot grant money or technology in formal gameplay"
	)
	_check(
		is_equal_approx(Engine.time_scale, 1.0) and _game.is_processing(),
		"opening restores normal speed and free play"
	)
	_game.run.candy = 100000
	_game._layout._show_technology()
	_check(_game.run.purchase_technology("cultivation"), "cultivation purchase succeeds")
	await get_tree().process_frame
	_check(_flow.kind == Flow.Kind.NONE, "teaching waits until the technology tree closes")
	_game._layout.close_panels()
	await _wait_talk(Flow.Kind.CULTIVATION)
	await _click()
	await _capture("cultivation")
	await _finish_dialogue()
	await _wait_idle()
	_advance_game_progress()
	await _wait_talk(Flow.Kind.AUTOMATION)
	await _finish_dialogue()
	await _wait_idle()
	_game.run.economy_changed.emit()
	await get_tree().process_frame
	_check(_flow.kind == Flow.Kind.NONE, "purchased technologies teach only once")
	for stage: int in range(3):
		if stage != 2 or "--queued-third" not in OS.get_cmdline_user_args():
			_advance_game_progress()
		if stage == 0:
			await _check_first_color_entrance()
		elif stage == 2:
			await _check_passive_third_color()
			continue
		await _wait_talk((Flow.Kind.COLOR_ONE + stage) as Flow.Kind)
		if stage == 1 and "--queued-third" in OS.get_cmdline_user_args():
			_advance_game_progress()
		await get_tree().create_timer(0.5, true, false, true).timeout
		_check(
			_flow.current_form == (2 if stage == 2 else 1),
			"visible transformation matches restoration stage"
		)
		if stage == 1 and "--early-confirm" in OS.get_cmdline_user_args():
			await _finish_dialogue()
			_check(_flow.phase == Flow.Phase.WAIT_COLOR, "early confirmation waits for restoration")
			await _wait_idle()
			_check(
				_game._restoration.completed_species.size() == 2 and not _game._view.is_overview(),
				"early confirmation still completes color and returns near"
			)
			continue
		if _flow.active_dialogue.phase == Dialogue.Phase.TYPING:
			await _click()
		await _capture("color_%d" % (stage + 1))
		var deadline: int = Time.get_ticks_msec() + 18000
		while (
			_game._restoration.completed_species.size() < stage + 1
			and Time.get_ticks_msec() < deadline
		):
			await get_tree().process_frame
		_check(
			_game._restoration.completed_species.size() == stage + 1,
			"restoration continues alongside automatic dialogue playback"
		)
		await _finish_dialogue()
		await _wait_idle()
		_check(
			not _game._view.is_overview() and not _game._view.presentation_locked,
			"each color returns automatically to near view after both tracks complete"
		)
	_check(
		not _game.run.is_complete and not _game._completion.visible,
		"third color does not bypass untamed nests or remaining monsters"
	)
	for nest: NestState in _game.run.nests:
		while not nest.is_tamed:
			_check(_game.run.upgrade_nest(nest.nest_id), "remaining nests can be automated")
	_check(
		not _game.run.is_complete,
		"all nests automated still requires collecting the remaining monsters"
	)
	# Final background restoration also stays passive once all three colors are restored.
	await get_tree().process_frame
	await get_tree().process_frame
	var background_deadline: int = Time.get_ticks_msec() + 10000
	while (
		_game._restoration.phase != Flow.Restoration.Phase.IDLE
		and Time.get_ticks_msec() < background_deadline
	):
		_check(
			(
				not _game._view.presentation_locked
				and not _game._view.is_overview()
				and _game.is_processing()
				and is_equal_approx(Engine.time_scale, 1.0)
			),
			"final background restoration does not interrupt free play"
		)
		await get_tree().process_frame
	_check(_game._restoration._background_complete, "background restoration still completes")
	_advance_game_progress()
	_check(_game.run.is_complete, "collecting the final monsters completes the run")
	var note_deadline: int = Time.get_ticks_msec() + 45000
	while not _flow.receipt.playing and Time.get_ticks_msec() < note_deadline:
		await get_tree().process_frame
	_check(_flow.receipt.playing, "White receipt precedes the rescue.")
	_check(not _game._restoration.core.is_processing(), "White core stops for receipt.")
	_check(not _game._victory.meteors.visible, "Meteors wait for receipt and rescue.")
	await _capture("receipt_typing")
	await _close_note(_flow.receipt)
	await _wait_talk(Flow.Kind.RESCUE, 45000)
	_check(
		(
			_game._victory.phase == _game.VictoryMeteors.Phase.WAITING
			and not _game._completion.visible
		),
		"rescue follows receipt and precedes meteors and credits"
	)
	await _click()
	await _capture("rescue")
	await _finish_dialogue()
	await _wait_idle()
	_check(_game._completion.visible, "credits begin after rescue is confirmed")
	_check(
		_started == [1, 2, 3, 4, 5, 7],
		"third color skips dialogue; other story beats stay in order"
	)
	_game._layout.restart_requested.emit()
	await _close_note(_flow.briefing)
	await _wait_talk(Flow.Kind.OPENING)
	_check(
		_flow.seen == [Flow.Kind.OPENING] and _flow.current_form == 0,
		"restart resets the story and cloak"
	)
	_game.story.cancel()
	_check(_flow._voice == null, "cancelling dialogue releases its voice")
	for slime: PrototypeSlime in _game._slimes:
		_check(is_equal_approx(slime.simulation_speed, 1.0), "cancel restores monster speed")
	_flow.restore_save({"seen": [], "form": 0, "resume": int(Flow.Kind.OPENING)})
	_check(is_equal_approx(Engine.time_scale, 0.5), "loaded dialogue restores background slowdown")
	for slime: PrototypeSlime in _game._slimes:
		_check(
			is_equal_approx(slime.simulation_speed * Engine.time_scale, 0.1),
			"loaded dialogue restores monster slowdown"
		)
	_game.queue_free()
	get_tree().current_scene = null
	await get_tree().process_frame
	await get_tree().process_frame
	_check(
		is_equal_approx(Engine.time_scale, 1.0), "exit during dialogue restores the global clock"
	)
	if _failures.is_empty():
		print(
			"PASS: story flow, first color completion and entrance delay, passive third color, purchases/flowers/victory, pause, restart and cleanup."
		)
	else:
		print("FAIL: ", _failures)
	get_tree().quit(0 if _failures.is_empty() else 1)


# Prepare progression through gameplay APIs; the shipped scene has no skip controls.
func _advance_game_progress() -> void:
	_game.run.candy = maxi(_game.run.candy, 100000)
	if _game.run.get_technology_level("automation") == 0:
		_check(_game.run.purchase_technology("automation"), "automation purchase succeeds")
		return
	for species: int in range(3):
		if species in _game._restoration.unlocked_species:
			continue
		var target: NestState
		for nest: NestState in _game.run.nests:
			if nest.species == species:
				target = nest
				break
		if target == null:
			_game.run._add_nest(
				species as NestState.Species,
				_game._planet.get_nest_position(2.0 if species == 1 else -2.0)
			)
			target = _game.run.nests.back()
		while not target.is_tamed:
			if not _game.run.upgrade_nest(target.nest_id):
				_check(false, "nest upgrade succeeds")
				return
		return
	var slimes: Array[PrototypeSlime] = _game._slimes.duplicate()
	for slime: PrototypeSlime in slimes:
		_game._finish_capture(slime)


func _check_first_color_entrance() -> void:
	var deadline: int = Time.get_ticks_msec() + 20000
	while _flow.phase != Flow.Phase.COLOR_CAMERA and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	_check(_flow.phase == Flow.Phase.COLOR_CAMERA, "first color waits for the overview camera")
	while _flow.phase == Flow.Phase.COLOR_CAMERA and Time.get_ticks_msec() < deadline:
		_check(
			not _flow.color_dialogue.visible, "mascot stays hidden through camera travel and fill"
		)
		_check(_game._view.presentation_locked, "camera travel and fill remain locked")
		await get_tree().process_frame
	_check(
		(
			_flow.phase == Flow.Phase.COLOR_DELAY
			and not _game._view.is_transitioning()
			and _game._restoration.completed_species.size() == 1
		),
		"entrance delay starts only after camera and color fill both finish"
	)
	_check(is_equal_approx(_flow.first_color_entrance_delay, 0.4), "entrance delay is 0.4 seconds")
	await _key(KEY_ESCAPE)
	var elapsed: float = _flow._elapsed
	await get_tree().create_timer(0.15, true, false, true).timeout
	_check(
		get_tree().paused and is_equal_approx(_flow._elapsed, elapsed),
		"pause freezes entrance delay"
	)
	await _key(KEY_ESCAPE)
	await _key(KEY_TAB)
	await _click()
	_check(_game._view.is_overview(), "input cannot leave overview during entrance delay")
	var remaining: float = _flow.first_color_entrance_delay - _flow._elapsed
	var before: int = Time.get_ticks_msec()
	while _flow.phase == Flow.Phase.COLOR_DELAY and Time.get_ticks_msec() < deadline:
		_check(not _flow.color_dialogue.visible, "mascot stays hidden during the delay")
		_check(
			_game._view.presentation_locked and not _game.is_processing(),
			"waiting keeps camera and gameplay locked"
		)
		await get_tree().process_frame
	var waited: float = float(Time.get_ticks_msec() - before) / 1000.0
	_check(absf(waited - remaining) < 0.10, "entrance delay uses real seconds at half world speed")
	_check(
		(
			_flow.color_dialogue.phase == Dialogue.Phase.ENTERING
			and _flow.color_dialogue.presenter.selected_form == 1
			and _flow.current_form == 1
		),
		"first visible entrance starts in muscle form before any dialogue line"
	)
	await get_tree().create_timer(0.25, true, false, true).timeout
	await _capture("first_color_entrance")
	_check(_flow._form_tween == null, "first color does not schedule a mid-dialogue disguise swap")


func _check_passive_third_color() -> void:
	var deadline: int = Time.get_ticks_msec() + 20000
	var starting_zoom: float = _game._view.target_zoom
	var starting_candy: int = _game.run.candy
	while Time.get_ticks_msec() < deadline:
		_check(
			(
				not _game._view.presentation_locked
				and _game.is_processing()
				and _game.is_processing_input()
				and is_equal_approx(Engine.time_scale, 1.0)
			),
			"third color leaves gameplay and inputs running at normal speed"
		)
		_check(
			(
				is_equal_approx(_game._view.target_zoom, starting_zoom)
				and not _game._view.is_transitioning()
			),
			"third color does not force a camera transition"
		)
		_check(
			_flow.phase == Flow.Phase.IDLE and not _flow.color_dialogue.visible,
			"third color does not interrupt play with a dialogue"
		)
		if (
			_game._restoration.completed_species.size() == 3
			and _game._restoration.phase == Flow.Restoration.Phase.IDLE
		):
			break
		await get_tree().process_frame
	_check(
		_game._restoration.completed_species.size() == 3,
		"third color completes without confirmation"
	)
	_check(_flow.current_form == 2, "later story uses the small form after the third color")
	_check(
		_game.run.candy > starting_candy, "automated nests keep producing throughout third color"
	)
	# Real keyboard input still controls the camera after the passive restoration.
	await _key(KEY_TAB)
	_check(_game._view.is_overview(), "player can still switch views")
	while _game._view.is_transitioning():
		await get_tree().process_frame
	await _key(KEY_TAB)
	while _game._view.is_transitioning():
		await get_tree().process_frame


func _wait_talk(expected: Flow.Kind, timeout_ms: int = 20000) -> void:
	var deadline: int = Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline:
		if (
			_flow.kind == expected
			and _flow.phase == Flow.Phase.TALKING
			and _flow.active_dialogue.phase == Dialogue.Phase.TYPING
		):
			for slime: PrototypeSlime in _game._slimes:
				_check(
					is_equal_approx(slime.simulation_speed * Engine.time_scale, 0.1),
					"every dialogue slows monsters to ten percent"
				)
			return
		await get_tree().process_frame
	_check(
		false,
		"timed out waiting for story %d (kind %d, phase %d)" % [expected, _flow.kind, _flow.phase]
	)


func _wait_idle() -> void:
	var deadline: int = Time.get_ticks_msec() + 20000
	while _flow.phase != Flow.Phase.IDLE and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	_check(_flow.phase == Flow.Phase.IDLE, "story releases its controls")
	for slime: PrototypeSlime in _game._slimes:
		_check(is_equal_approx(slime.simulation_speed, 1.0), "story restores monster speed")


func _finish_dialogue() -> void:
	var deadline: int = Time.get_ticks_msec() + 10000
	while _flow.phase == Flow.Phase.TALKING and Time.get_ticks_msec() < deadline:
		_check(
			(
				_flow.active_dialogue.text_label.get_content_height()
				<= _flow.active_dialogue.text_label.size.y
			),
			"each complete line fits its bubble"
		)
		await _click()
		await get_tree().process_frame


func _click() -> void:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = get_viewport().get_visible_rect().size * Vector2(0.08, 0.65)
	event.pressed = true
	Input.parse_input_event(event)
	await get_tree().process_frame
	event = event.duplicate() as InputEventMouseButton
	event.pressed = false
	Input.parse_input_event(event)
	await get_tree().process_frame


func _key(code: Key) -> void:
	var event: InputEventKey = InputEventKey.new()
	event.keycode = code
	event.pressed = true
	Input.parse_input_event(event)
	await get_tree().process_frame
	event = event.duplicate() as InputEventKey
	event.pressed = false
	Input.parse_input_event(event)
	await get_tree().process_frame


func _capture(label: String) -> void:
	if "--capture" not in OS.get_cmdline_user_args():
		return
	if (
		"--note-capture" in OS.get_cmdline_user_args()
		and label not in ["briefing", "briefing_typing", "receipt", "receipt_typing", "rescue"]
	):
		return
	DirAccess.make_dir_recursive_absolute(_output)
	for dimensions: Vector2i in [Vector2i(1920, 1080), Vector2i(1280, 800)]:
		get_window().size = dimensions
		await get_tree().process_frame
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var filename: String = "%s/%s_%dx%d.png" % [_output, label, dimensions.x, dimensions.y]
		get_viewport().get_texture().get_image().save_png(filename)
		print("CAPTURE: ", filename)
	_check(
		(
			_flow.active_dialogue.text_label.get_content_height()
			<= _flow.active_dialogue.text_label.size.y
		),
		"dialogue text fits its bubble"
	)


func _check(passed: bool, message: String) -> void:
	if not passed:
		_failures.append(message)
		push_error(message)


func _timeout() -> void:
	push_error("Story flow check timed out.")
	get_tree().quit(1)


func _close_note(notice: Flow.Notice) -> void:
	_check(notice.playing, "Note is waiting for the player.")
	await get_tree().create_timer(0.8).timeout
	if not notice.white_paper:
		await _capture("briefing_typing")
	await _click()
	_check(notice.phase == Flow.Notice.Phase.READING, "First click reveals the note.")
	await _capture("receipt" if notice.white_paper else "briefing")
	notice.close()
	await notice.finished
