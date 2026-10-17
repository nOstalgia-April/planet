extends Node

const Game = preload("res://features/tutorial_intro/tutorial_game.gd")
const Tutorial = preload("res://features/tutorial_intro/tutorial_intro.gd")
const Dialogue = preload("res://scripts/ui/mascot_dialogue.gd")
const GAME_PATH: String = "res://features/tutorial_intro/tutorial_game.tscn"
const EXPECTED_LINES: PackedStringArray = [
	"喂——小心脚下！你差点踩到我们家刚冒出来的小家伙的巢穴！",
	"你是……清扫员？来帮我们治理巢穴和生态的？",
	"太好了！这里吃得好、住得好，就是大家生得有点太好了。",
	"我刚数完这一窝，那边又冒出来三窝。喊都喊不回来！",
	"这些小家伙吃糖，也会产糖。糖能给飞船和工具供能。",
	"尤其是这里的糖！吃完以后，连我都比以前有精神了。",
	"你帮我把外面乱跑的家伙收拢一下，再整理整理巢穴就行。",
	"动作轻一点啊。它们只是比较活泼……还有比较多。",
	"你手上那个就是吸尘器？先试着把这几只乱跑的收进去吧。",
	"……哦，原来里面装得下！那我就放心了。",
	"收获的这些糖你就拿着吧，算帮忙的报酬。别全吃了，听说你们那里可以用糖果升级科技。",
	"拿糖给吸尘器和捕捉网升升级，干活能省不少力气。",
	"不过先说好，叫出来多少，你可得接住多少。",
]
const EXPECTED_INDICES: PackedInt32Array = [0, 1, 2, 3, 4, 5, 6, 7, 0, 0, 0, 1, 2]

var _game: Game
var _tutorial: Tutorial
var _dialogue: Dialogue
var _compact_dialogue: Dialogue
var _failures: PackedStringArray = []
var _phases: PackedInt32Array = []
var _started_indices: PackedInt32Array = []
var _started_texts: PackedStringArray = []
var _finished_indices: PackedInt32Array = []
var _completion_count: int = 0
var _capture_count: int = 0
var _capture_reward: int = 0
var _feedback_finished_count: int = 0
var _transport_finished_count: int = 0
var _transport_cancelled_count: int = 0
var _compact_finished_count: int = 0
var _last_feedback: CollectionEffect
var _frozen_transform: Transform2D
var _frozen_spawn_clocks: PackedFloat64Array = []
var _frozen_candy: int = 0
var _frozen_capture_count: int = 0
var _capture_enabled: bool = false
var _output_directory: String = ""
var _captures: Array[Dictionary] = []
var _recording: bool = true
var _capturing_layout: bool = false


func _ready() -> void:
	_run.call_deferred()


func _process(_delta: float) -> void:
	if _tutorial == null or _capturing_layout:
		return
	# Repeated clicks during the reading pause must not bypass automatic continuation.
	for speaker: Dialogue in [_dialogue, _compact_dialogue]:
		if speaker.phase == Dialogue.Phase.HOLDING and speaker._phase_elapsed >= 0.45:
			_click(Vector2(80.0, 180.0))
	if (
		_tutorial.phase
		in [Tutorial.Phase.REACTION, Tutorial.Phase.REWARD_WAIT, Tutorial.Phase.CLOSING]
	):
		_check_frozen_closing()


func _run() -> void:
	_capture_enabled = "--capture" in OS.get_cmdline_user_args()
	if _capture_enabled and DisplayServer.get_name() == "headless":
		_check(false, "--capture requires a graphical renderer.")
		_finish()
		return
	get_tree().root.mode = Window.MODE_WINDOWED
	get_tree().root.size = Vector2i(1280, 800)
	if _capture_enabled:
		_prepare_output()
	var packed: PackedScene = load(GAME_PATH) as PackedScene
	_game = packed.instantiate() as Game
	packed = null
	_tutorial = _game.get_node("TutorialIntro") as Tutorial
	_dialogue = _tutorial.get_node("TutorialLayer/MascotDialogue") as Dialogue
	_compact_dialogue = _tutorial.get_node("TutorialLayer/CompactDialogue") as Dialogue
	for speaker: Dialogue in [_dialogue, _compact_dialogue]:
		speaker.characters_per_second = 1000.0
		speaker.punctuation_pause = 0.0
		speaker.line_started.connect(_on_line_started)
		speaker.line_finished.connect(_on_line_finished)
	_tutorial.phase_changed.connect(_on_phase_changed)
	_tutorial.completed.connect(_on_completed)
	_compact_dialogue.dialogue_finished.connect(_on_compact_finished)
	_game.vacuum_capture_completed.connect(_on_capture_completed)
	get_tree().root.add_child(_game)
	_game._pipe.transport_finished.connect(_on_transport_finished)
	_game._pipe.transport_cancelled.connect(_on_transport_cancelled)
	if await _check_opening():
		if await _check_tool_gate():
			await _check_capture_and_completion()
	_recording = false
	await _check_early_capture()
	await _check_cancel_during_feedback()
	await _check_restart_cleanup()
	_tutorial.cancel()
	_game.queue_free()
	_game = null
	_tutorial = null
	_dialogue = null
	_compact_dialogue = null
	await get_tree().process_frame
	await get_tree().process_frame
	_finish()


func _check_opening() -> bool:
	_check(_tutorial.phase == Tutorial.Phase.OVERVIEW, "The real scene starts in OVERVIEW.")
	_check(_game.run.nests.size() == 2, "The opening contains exactly two nests.")
	_check(_game._slimes.is_empty() and _game.run.candy == 0, "Opening nests start empty.")
	for nest: NestView in _game._nest_views:
		_check(nest.emergence_progress == 0.0, "Both opening nests begin beneath the surface.")
	var initial_rotation: float = _game._world.rotation
	await _wait_seconds(0.2)
	_check(
		not is_equal_approx(_game._world.rotation, initial_rotation),
		"The overview naturally rotates before zooming."
	)
	_check_locked_input()
	_check(_game._view.is_overview(), "Blocked input preserves the opening overview.")
	_check_dock_offscreen()
	await _capture_stage("01_overview")
	if not await _wait_for_phase(Tutorial.Phase.ZOOMING):
		return false
	_check(_game._view.is_transitioning(), "ZOOMING uses the real camera transition.")
	_check_locked_input()
	_check(_game._view.target_zoom == 1.0, "Blocked input cannot reverse the tutorial zoom.")
	await _capture_stage("02_zooming")
	if not await _wait_for_phase(Tutorial.Phase.EMERGING):
		return false
	_check_locked_input()
	await _wait_seconds(_tutorial.emergence_seconds * 0.45)
	for nest: NestView in _game._nest_views:
		_check(
			nest.emergence_progress > 0.0 and nest.emergence_progress < 1.0,
			"Both opening nests unfold from the surface together."
		)
	_check(_game._slimes.is_empty(), "Neither nest produces before unfolding finishes.")
	_check(
		not _dialogue.visible and Engine.time_scale == 1.0,
		"Emergence precedes the mascot and slowdown."
	)
	await _capture_stage("02a_emerging")
	if not await _wait_for_phase(Tutorial.Phase.WAIT_LANDING):
		return false
	_check(
		_game.run.nests[0].alive_slimes > 0 and _game.run.nests[1].alive_slimes > 0,
		"Both real nests produce their first burst in the same frame."
	)
	for slime: PrototypeSlime in _game._slimes:
		_check(slime._launch_elapsed < slime.launch_seconds, "Both bursts begin in flight.")
	# One slower actor proves the gate follows every actual landing, not a fixed timer.
	var last_slime: PrototypeSlime = _game._slimes.back()
	last_slime.launch_seconds = 0.85
	var opening_population: int = _game._slimes.size()
	await _wait_seconds(0.48)
	_check(
		_tutorial.phase == Tutorial.Phase.WAIT_LANDING, "Slowing waits for the last airborne slime."
	)
	_check(
		Engine.time_scale == 1.0 and not _dialogue.visible,
		"Flight stays at normal speed with the mascot hidden."
	)
	_check_locked_input()
	await _capture_stage("02b_wait_landing")
	if not await _wait_for_phase(Tutorial.Phase.SLOWING):
		return false
	for slime: PrototypeSlime in _game._slimes:
		_check(
			slime._launch_elapsed >= slime.launch_seconds,
			"Every opening slime lands before slowing."
		)
	var lowest_scale: float = Engine.time_scale
	var deadline: int = Time.get_ticks_msec() + 5000
	while _tutorial.phase == Tutorial.Phase.SLOWING and Time.get_ticks_msec() < deadline:
		lowest_scale = minf(lowest_scale, Engine.time_scale)
		await get_tree().process_frame
	_check(lowest_scale < 0.5, "SLOWING gradually reduces the engine time scale.")
	_check(_tutorial.phase == Tutorial.Phase.INTRO, "SLOWING naturally reaches INTRO.")
	if _tutorial.phase != Tutorial.Phase.INTRO:
		return false
	_check(is_equal_approx(Engine.time_scale, 1.0), "INTRO restores the engine time scale.")
	_check(get_tree().paused, "INTRO freezes the gameplay tree.")
	_check_dock_offscreen()
	_check_locked_input()
	var frozen_transform: Transform2D = _game._world.transform
	var frozen_clock: float = _game.run.nests[0].spawn_clock
	await _wait_seconds(0.2)
	_check(_game._world.transform == frozen_transform, "The world stays still during INTRO.")
	_check(
		(
			_game.run.nests[0].spawn_clock == frozen_clock
			and _game._slimes.size() == opening_population
		),
		"The landed opening population stays frozen without additional production."
	)
	if not await _wait_for_line(0):
		return false
	await _capture_stage("03_intro")
	if not await _wait_for_phase(Tutorial.Phase.DOCK):
		return false
	_check(
		_started_texts == EXPECTED_LINES.slice(0, 8), "Left clicks confirm all eight intro lines."
	)
	_check(_game.run.candy == 0, "The introductory dialogue grants no candy.")
	_check_locked_input()
	await _wait_seconds(0.2)
	_check(
		_game._layout.dock_intro_progress > 0.0,
		"The tool dock naturally moves into view after the introductory dialogue."
	)
	await _capture_stage("04_dock_entering")
	return await _wait_for_phase(Tutorial.Phase.WAIT_TOOL)


func _check_tool_gate() -> bool:
	var opening_population: int = _game._slimes.size()
	_check(get_tree().paused, "WAIT_TOOL keeps gameplay frozen.")
	_check(_tutorial.spotlight.visible, "WAIT_TOOL displays the spotlight.")
	_check(_game._quick_pipe_button.is_visible_in_tree(), "The real vacuum button is visible.")
	_check(
		get_viewport().get_visible_rect().encloses(_game._quick_pipe_button.get_global_rect()),
		"The vacuum button has finished entering the viewport."
	)
	await _capture_stage("05_wait_tool", true)
	_click(Vector2(80.0, 180.0))
	_click(_control_center(_game.get_node("HUD/Interface/ToolDock/Technology") as Control))
	_key(KEY_ESCAPE)
	_key(KEY_TAB)
	_game._quick_pipe_button.grab_focus()
	_key(KEY_SPACE)
	await get_tree().process_frame
	_check(
		_tutorial.phase == Tutorial.Phase.WAIT_TOOL, "Wrong clicks and keys cannot choose the tool."
	)
	_check(
		not _game._layout.is_technology_open(),
		"The frozen technology button cannot open its panel."
	)
	_check(not _game._layout._manual_pause, "Blocked Escape does not leave a manual pause behind.")
	var center: Vector2 = _control_center(_game._quick_pipe_button)
	_mouse_button(center, true)
	_mouse_motion(center + Vector2(0.0, -200.0), MOUSE_BUTTON_MASK_LEFT)
	_mouse_button(center + Vector2(0.0, -200.0), false)
	await get_tree().process_frame
	_check(
		_tutorial.phase == Tutorial.Phase.WAIT_TOOL,
		"Releasing outside cancels the real button press."
	)
	_check(
		_game._slimes.size() == opening_population,
		"Cancelled selection preserves the frozen opening population."
	)
	_click(center)
	_check(_tutorial.phase == Tutorial.Phase.VACUUM, "Only the real vacuum click starts gameplay.")
	_check(not get_tree().paused, "Choosing the tool unfreezes gameplay.")
	_check(
		_game.is_processing() and _game.is_processing_input(),
		"Choosing the tool restores gameplay processing and input."
	)
	_check(not _tutorial.spotlight.visible, "The spotlight disappears after tool selection.")
	_check(not _dialogue.visible, "Choosing the tool hides the large dialogue completely.")
	_check(_compact_dialogue.visible, "The playable trial uses the compact upper dialogue.")
	if _tutorial.phase != Tutorial.Phase.VACUUM:
		return false
	# The trial starts with the same actors that landed before the introduction.
	_game.set_process(false)
	_check(
		_game.run.nests[0].alive_slimes > 0 and _game.run.nests[1].alive_slimes > 0,
		"Both opening populations are immediately available after choosing the vacuum."
	)
	_check(_game._slimes.size() >= 2, "Production spawn signals create real monster actors.")
	if not await _wait_for_line(0, _compact_dialogue):
		return false
	await _check_compact_layout_sizes()
	await _capture_stage("06_compact_trial", true)
	return true


func _check_capture_and_completion() -> void:
	if not await _wait_for_phase(Tutorial.Phase.WAIT_CAPTURE):
		return
	_check(not _tutorial.first_capture_seen, "Finishing the vacuum instruction is not a capture.")
	_check(_game.run.candy == 0, "Instruction and spawning grant no candy.")
	var population_before: int = _game._slimes.size()
	var feedback_before: int = _feedback_finished_count
	var transport_before: int = _transport_finished_count
	if not await _capture_one():
		return
	_check(_tutorial.first_capture_seen, "A real suction completion records the first capture.")
	_check(
		_tutorial.phase == Tutorial.Phase.CAPTURE_FEEDBACK,
		"A completed suction waits for its visible feedback before the reaction."
	)
	_check(not get_tree().paused, "Capture feedback plays before the tree is frozen.")
	_check(is_equal_approx(Engine.time_scale, 1.0), "The capture feedback plays at normal speed.")
	_check(not _dialogue.visible, "The large dialogue stays hidden during the capture feedback.")
	_check(is_instance_valid(_last_feedback), "The capture hands off its actual reward flight.")
	_check(_game._pipe.visible, "The actual pipe transport remains visible after the capture.")
	_check_locked_input()
	_check(
		_game._slimes.size() == population_before - 1, "The captured actor is removed exactly once."
	)
	_check(
		_capture_count == 1 and _capture_reward > 0,
		"The production capture event reports earned candy."
	)
	await _capture_stage("07_capture_feedback")
	if not await _wait_for_phase(Tutorial.Phase.REACTION_SLOWING):
		return
	_check(
		_feedback_finished_count == feedback_before + 1,
		"The actual reward flight finishes before slowing begins."
	)
	_check(
		_transport_finished_count == transport_before + 1,
		"The actual pipe transport finishes before slowing begins."
	)
	_check(not get_tree().paused, "Reaction slowing precedes the frozen dialogue.")
	_check_locked_input()
	var lowest_scale: float = Engine.time_scale
	var slowing_deadline: int = Time.get_ticks_msec() + 5000
	while (
		_tutorial.phase == Tutorial.Phase.REACTION_SLOWING
		and Time.get_ticks_msec() < slowing_deadline
	):
		lowest_scale = minf(lowest_scale, Engine.time_scale)
		await get_tree().process_frame
	_check(lowest_scale < 0.5, "The first capture visibly slows down before freezing.")
	if not await _wait_for_phase(Tutorial.Phase.REACTION):
		return
	if not await _wait_for_line(0):
		return
	_check_locked_input()
	await _capture_stage("08_first_capture_reaction")
	if not await _wait_for_phase(Tutorial.Phase.REWARD_WAIT):
		return
	_check(_game.run.candy == _capture_reward, "The reaction adds no candy beyond capture rewards.")
	_check_locked_input()
	await _capture_stage("09_frozen_reading_pause")
	if not await _wait_for_phase(Tutorial.Phase.CLOSING):
		return
	for index: int in range(3):
		if not await _wait_for_line(index):
			return
		_check_locked_input()
		_check(
			_dialogue.text_label.get_content_height() <= _dialogue.text_label.size.y,
			"Each complete closing line fits without clipping."
		)
		await _capture_stage("10_frozen_closing_%d" % (index + 1), index == 0)
	if not await _wait_for_phase(Tutorial.Phase.RESUMING):
		return
	_check(
		not get_tree().paused, "Only the end of all closing lines releases the presentation pause."
	)
	_check(_game.is_processing(), "RESUMING restores the gameplay driver.")
	_check(
		not _dialogue.visible and not _compact_dialogue.visible,
		"RESUMING hides both dialogue modes."
	)
	_check(Engine.time_scale < 0.2, "RESUMING starts at the slow presentation speed.")
	_check_locked_input()
	var previous_scale: float = Engine.time_scale
	var resume_deadline: int = Time.get_ticks_msec() + 5000
	while _tutorial.phase == Tutorial.Phase.RESUMING and Time.get_ticks_msec() < resume_deadline:
		_check(
			Engine.time_scale >= previous_scale,
			"The resume transition smoothly restores normal speed."
		)
		previous_scale = Engine.time_scale
		await get_tree().process_frame
	if not await _wait_for_phase(Tutorial.Phase.DONE):
		return
	_check(
		_started_texts == EXPECTED_LINES, "Every original dialogue line plays once in exact order."
	)
	_check(
		_started_indices == EXPECTED_INDICES,
		"Each dialogue group starts with the expected indices."
	)
	_check(_finished_indices == EXPECTED_INDICES, "Every dialogue line finishes once in order.")
	_check(
		_phases.count(Tutorial.Phase.REACTION) == 1, "Repeated captures cannot replay the reaction."
	)
	_check(_completion_count == 1, "The tutorial completes once.")
	_check(_phases.count(Tutorial.Phase.RESUMING) == 1, "The frozen closing segment resumes once.")
	_check(is_equal_approx(Engine.time_scale, 1.0), "DONE restores the original time scale.")
	_check(_capture_count == 1, "No additional capture settles during the frozen dialogue segment.")
	_check(_game.run.candy == _capture_reward, "Closing dialogue grants no extra reward or gift.")
	_check(
		not _dialogue.visible and not _compact_dialogue.visible and not _tutorial.spotlight.visible,
		"DONE hides both dialogue modes and the spotlight."
	)
	_check(not _game._view.presentation_locked, "DONE releases the camera lock.")
	_check(_game.is_processing_input(), "DONE restores ordinary gameplay input.")
	await _capture_one()
	_check(_capture_count == 2, "A second real capture settles normally after the entire tutorial.")
	_check(
		_tutorial.phase == Tutorial.Phase.DONE,
		"Later captures cannot replay the first-capture reaction."
	)
	_check(
		_completion_count == 1, "A later real capture does not emit another tutorial completion."
	)
	_game.set_process(true)
	_mouse_motion(Vector2(30.0, 30.0))
	await get_tree().process_frame
	_key(KEY_ESCAPE)
	await get_tree().process_frame
	_check(get_tree().paused, "Ordinary Escape can pause after the tutorial.")
	_key(KEY_ESCAPE)
	await get_tree().process_frame
	_check(not get_tree().paused, "Ordinary Escape can resume after the tutorial.")
	_key(KEY_TAB)
	await get_tree().process_frame
	_check(_game._view.target_zoom == 0.0, "Ordinary Tab switches to overview after the tutorial.")
	await _capture_stage("11_done")


func _capture_one() -> bool:
	var was_processing: bool = _game.is_processing()
	_game.set_process(false)
	_game._pipe.show()
	var before: int = _capture_count
	var deadline: int = Time.get_ticks_msec() + 4000
	while _capture_count == before and Time.get_ticks_msec() < deadline:
		if _game._slimes.is_empty():
			break
		var target: PrototypeSlime = _game._slimes[0]
		_game._pipe.set_tool_state(target.get_capture_point(), target.get_capture_point(), true)
		_game._capture_at(0.1, target.get_capture_point(), true)
		if _capture_count == before:
			await get_tree().process_frame
	_check(_capture_count == before + 1, "Real suction completes within its deadline.")
	if _tutorial.phase in [Tutorial.Phase.VACUUM, Tutorial.Phase.WAIT_CAPTURE, Tutorial.Phase.DONE]:
		_game.set_process(was_processing)
	return _capture_count == before + 1


func _check_early_capture() -> void:
	_compact_dialogue.characters_per_second = 10.0
	if not await _begin_another_trial():
		return
	var compact_before: int = _compact_finished_count
	var feedback_before: int = _feedback_finished_count
	var transport_before: int = _transport_finished_count
	var cancelled_before: int = _transport_cancelled_count
	if not await _capture_one():
		return
	_check(
		_tutorial.phase == Tutorial.Phase.CAPTURE_FEEDBACK,
		"An early capture enters the feedback wait."
	)
	_check(
		_compact_finished_count == compact_before,
		"The early capture really occurs before the trial instruction has finished."
	)
	_game._on_window_focus_exited()
	_check(
		_transport_cancelled_count == cancelled_before + 1,
		"Losing window focus cancels the actual in-flight pipe transport."
	)
	_check(
		_transport_finished_count == transport_before,
		"A cancelled transport is never reported as a naturally finished transport."
	)
	await _wait_seconds(0.15)
	_check(
		_tutorial.phase == Tutorial.Phase.CAPTURE_FEEDBACK and not get_tree().paused,
		"A cancelled transport still waits for the reward flight and unfinished trial instruction."
	)
	if not await _wait_for_phase(Tutorial.Phase.REACTION_SLOWING):
		return
	_check(
		_feedback_finished_count == feedback_before + 1,
		"The early capture's real candy flight finishes."
	)
	_check(
		_compact_finished_count == compact_before + 1,
		"The early trial instruction finishes before slowing."
	)
	await _wait_seconds(0.15)
	_check(Engine.time_scale < 1.0, "The early capture also reaches an active slowdown.")
	if not await _wait_for_phase(Tutorial.Phase.REACTION):
		return
	_check(
		get_tree().paused,
		"The early capture and cancelled transport still reach the frozen reaction."
	)
	_game._on_window_focus_entered()
	_tutorial.cancel()
	_check_cancelled_state()
	_compact_dialogue.characters_per_second = 1000.0


func _check_cancel_during_feedback() -> void:
	if not await _begin_another_trial():
		return
	if not await _capture_one():
		return
	_check(
		is_instance_valid(_last_feedback),
		"Cancellation is checked while actual feedback is still pending."
	)
	_tutorial.cancel()
	_check_cancelled_state()
	# Keep pointer-driven captures out of this cleanup observation; child feedback still runs.
	_game.set_process(false)
	await _wait_seconds(1.0)
	_check(
		_tutorial.phase == Tutorial.Phase.IDLE,
		"Completing old feedback after cancellation cannot restart the reaction."
	)
	_check(
		not get_tree().paused and is_equal_approx(Engine.time_scale, 1.0),
		"Old feedback cannot reclaim pause or time scale."
	)
	_game.restart_run()
	_check_fresh_restart()


func _begin_another_trial() -> bool:
	_game.restart_run()
	_check_fresh_restart()
	if not await _wait_for_phase(Tutorial.Phase.WAIT_TOOL, 14000):
		return false
	_click(_control_center(_game._quick_pipe_button))
	_check(
		_tutorial.phase == Tutorial.Phase.VACUUM,
		"The next check enters its trial through the real tool button."
	)
	_game.set_process(false)
	_check(not _game._slimes.is_empty(), "The next trial uses a real nest-produced monster.")
	return _tutorial.phase == Tutorial.Phase.VACUUM and not _game._slimes.is_empty()


func _check_cancelled_state() -> void:
	_check(_tutorial.phase == Tutorial.Phase.IDLE, "Cancel leaves the director idle.")
	_check(not get_tree().paused, "Cancel releases the presentation pause.")
	_check(is_equal_approx(Engine.time_scale, 1.0), "Cancel restores the global time scale.")
	_check(
		(
			_game.is_processing()
			and _game.is_processing_input()
			and not _game._view.presentation_locked
		),
		"Cancel restores gameplay processing, input and the camera."
	)
	_check(
		not _dialogue.visible and not _compact_dialogue.visible and not _tutorial.spotlight.visible,
		"Cancel clears both dialogue modes and the spotlight."
	)


func _check_frozen_closing() -> void:
	_check(get_tree().paused, "The reaction, reading pause and all closing lines stay frozen.")
	_check(
		is_equal_approx(Engine.time_scale, 1.0),
		"The frozen segment leaves no slow-motion scale behind."
	)
	_check(
		not _game.is_processing() and not _game.is_processing_input(),
		"The entire frozen segment disables the gameplay driver and input."
	)
	_check(_game._view.presentation_locked, "The entire frozen segment keeps the camera locked.")
	_check(
		not _compact_dialogue.visible,
		"The frozen large dialogue replaces the compact trial dialogue."
	)
	_check(
		_game._world.transform == _frozen_transform,
		"The world stays fixed throughout the frozen segment."
	)
	_check(
		_game.run.candy == _frozen_candy and _capture_count == _frozen_capture_count,
		"The frozen segment cannot collect further monsters or candy."
	)
	for index: int in range(_frozen_spawn_clocks.size()):
		_check(
			_game.run.nests[index].spawn_clock == _frozen_spawn_clocks[index],
			"Nest production remains frozen throughout reaction and closing."
		)


func _check_compact_layout_sizes() -> void:
	var processing: bool = _compact_dialogue.is_processing()
	var presenter_paused: bool = _compact_dialogue.presenter.paused
	_compact_dialogue.set_process(false)
	_compact_dialogue.presenter.paused = true
	for resolution: Vector2i in [Vector2i(1280, 800), Vector2i(1920, 1080)]:
		get_tree().root.size = resolution
		await get_tree().process_frame
		await get_tree().process_frame
		_check_compact_layout()
	get_tree().root.size = Vector2i(1280, 800)
	await get_tree().process_frame
	await get_tree().process_frame
	_compact_dialogue.set_process(processing)
	_compact_dialogue.presenter.paused = presenter_paused


func _compact_visual_rect() -> Rect2:
	var bounds: Rect2 = _compact_dialogue.bubble.get_global_rect()
	if _compact_dialogue.presenter.visible:
		var portrait: Rect2 = (
			_compact_dialogue.presenter.sprite.get_global_transform_with_canvas()
			* _compact_dialogue.presenter.resting_bounds[_compact_dialogue.presenter.selected_form]
		)
		bounds = bounds.merge(portrait)
	return bounds


func _check_compact_layout() -> void:
	var viewport: Rect2 = get_viewport().get_visible_rect()
	var bounds: Rect2 = _compact_visual_rect()
	_check(
		viewport.encloses(bounds),
		"The complete compact portrait and bubble remain in the viewport."
	)
	_check(
		bounds.end.y < viewport.size.y * 0.4,
		"The compact dialogue stays in the upper part of the screen."
	)
	var protected_controls: Array[Control] = [
		_game.get_node("HUD/Interface/Economy") as Control,
		_game.get_node("HUD/Interface/GameMenu/Toolbar") as Control,
		_game.get_node("HUD/Interface/ToolDock") as Control,
	]
	for control: Control in protected_controls:
		_check(
			not bounds.intersects(control.get_global_rect()),
			"The compact dialogue clears the resource readout, menu and bottom tool dock."
		)
	for nest: NestView in _game._nest_views:
		_check(
			not bounds.intersects(nest.get_hover_rect()),
			"The compact dialogue does not cover either tutorial nest."
		)
	_check(
		_compact_dialogue.text_label.get_content_height() <= _compact_dialogue.text_label.size.y,
		"The complete trial instruction fits the compact text area."
	)


func _check_restart_cleanup() -> void:
	_game.restart_run()
	_check_fresh_restart()
	if not await _wait_for_phase(Tutorial.Phase.EMERGING):
		return
	_tutorial.cancel()
	_check_cancelled_state()
	for nest: NestView in _game._nest_views:
		_check(nest.emergence_progress == 1.0, "Cancellation leaves fully revealed nests.")
	_game.restart_run()
	if not await _wait_for_phase(Tutorial.Phase.WAIT_LANDING):
		return
	_game.restart_run()
	_check_fresh_restart()
	if not await _wait_for_phase(Tutorial.Phase.SLOWING):
		return
	await _wait_seconds(0.15)
	_check(Engine.time_scale < 1.0, "Restart test reaches an active slowdown.")
	_game.restart_run()
	_check_fresh_restart()
	if not await _wait_for_phase(Tutorial.Phase.INTRO):
		return
	_check(get_tree().paused, "Restart test reaches the frozen introduction.")
	_game.restart_run()
	_check_fresh_restart()


func _check_fresh_restart() -> void:
	_check(_tutorial.phase == Tutorial.Phase.OVERVIEW, "Restart begins a clean overview.")
	_check(not get_tree().paused, "Restart removes the previous presentation pause.")
	_check(is_equal_approx(Engine.time_scale, 1.0), "Restart restores the original time scale.")
	_check(not _tutorial.first_capture_seen, "Restart clears the first-capture flag.")
	_check(_game.run.candy == 0 and _game._slimes.is_empty(), "Restart clears candy and actors.")
	_check(_tutorial._opening_airborne.is_empty(), "Restart disconnects old landing waits.")
	for nest: NestView in _game._nest_views:
		_check(nest.emergence_progress == 0.0, "Restart resets both nest emergence effects.")
	_check(
		not _dialogue.visible and not _compact_dialogue.visible and not _tutorial.spotlight.visible,
		"Restart clears both old dialogue modes and the spotlight."
	)
	_check(not _game.is_processing_input(), "Restart restores the opening input gate.")
	_check_dock_offscreen()


func _check_locked_input() -> void:
	var zoom: float = _game._view.target_zoom
	var paused: bool = get_tree().paused
	_key(KEY_ESCAPE)
	_key(KEY_TAB)
	var dialogue_phase: Dialogue.Phase = _dialogue.phase
	var dialogue_index: int = _dialogue.line_index
	var compact_phase: Dialogue.Phase = _compact_dialogue.phase
	var compact_index: int = _compact_dialogue.line_index
	_click(_control_center(_game.get_node("HUD/Interface/GameMenu/Toolbar/Pause") as Control))
	_check(
		_dialogue.phase == dialogue_phase and _dialogue.line_index == dialogue_index,
		"Menu buttons cannot advance the large dialogue, including while gameplay is frozen."
	)
	_check(
		_compact_dialogue.phase == compact_phase and _compact_dialogue.line_index == compact_index,
		"Menu buttons cannot advance the compact dialogue."
	)
	_check(get_tree().paused == paused, "Opening input cannot change the pause state.")
	_check(_game._view.target_zoom == zoom, "Opening input cannot change the target view.")
	_check(not _game.is_processing_input(), "Opening gameplay input stays disabled.")
	_check(not _game._layout._manual_pause, "Opening input cannot set a manual pause.")


func _check_dock_offscreen() -> void:
	_check(
		(
			_game._layout._tool_dock.get_global_rect().position.y
			>= get_viewport().get_visible_rect().end.y
		),
		"The tool dock stays below the viewport before its entrance."
	)


func _wait_for_phase(expected: Tutorial.Phase, timeout_msec: int = 9000) -> bool:
	var deadline: int = Time.get_ticks_msec() + timeout_msec
	while _tutorial.phase != expected and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	var reached: bool = _tutorial.phase == expected
	_check(reached, "Natural sequence reaches %s before timeout." % Tutorial.Phase.keys()[expected])
	return reached


func _wait_for_line(index: int, speaker: Dialogue = null) -> bool:
	if speaker == null:
		speaker = _dialogue
	var deadline: int = Time.get_ticks_msec() + 3000
	while Time.get_ticks_msec() < deadline:
		if speaker.line_index == index and speaker.phase == Dialogue.Phase.HOLDING:
			return true
		await get_tree().process_frame
	_check(false, "The requested line naturally reaches its reading pause.")
	return false


func _wait_seconds(seconds: float) -> void:
	var deadline: int = Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		await get_tree().process_frame


func _control_center(control: Control) -> Vector2:
	return control.get_global_transform_with_canvas() * (control.size * 0.5)


func _click(position: Vector2) -> void:
	_mouse_motion(position)
	_mouse_button(position, true)
	_mouse_button(position, false)


func _mouse_button(position: Vector2, pressed: bool) -> void:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.position = position
	event.global_position = position
	event.button_index = MOUSE_BUTTON_LEFT
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	event.pressed = pressed
	get_viewport().push_input(event, true)


func _mouse_motion(position: Vector2, mask: int = 0) -> void:
	var event: InputEventMouseMotion = InputEventMouseMotion.new()
	event.position = position
	event.global_position = position
	event.button_mask = mask
	get_viewport().push_input(event, true)


func _key(code: Key) -> void:
	var event: InputEventKey = InputEventKey.new()
	event.keycode = code
	event.pressed = true
	get_viewport().push_input(event, true)
	var release: InputEventKey = event.duplicate() as InputEventKey
	release.pressed = false
	get_viewport().push_input(release, true)


func _capture_stage(label: String, both_sizes: bool = false) -> void:
	if not _capture_enabled:
		return
	_capturing_layout = true
	var game_processing: bool = _game.is_processing()
	var view_processing: bool = _game._view.is_processing()
	var pipe_process_mode: Node.ProcessMode = _game._pipe.process_mode
	var effects_process_mode: Node.ProcessMode = _game._effects.process_mode
	var slimes_process_mode: Node.ProcessMode = _game._slime_root.process_mode
	var tutorial_processing: bool = _tutorial.is_processing()
	var dialogue_processing: bool = _dialogue.is_processing()
	var compact_processing: bool = _compact_dialogue.is_processing()
	var presenter_paused: bool = _dialogue.presenter.paused
	var compact_presenter_paused: bool = _compact_dialogue.presenter.paused
	for speaker: Dialogue in [_dialogue, _compact_dialogue]:
		if speaker.phase == Dialogue.Phase.HOLDING:
			# Capture after the last glyph's visual pop, without advancing the dialogue.
			speaker._glyph_pop.clock += speaker._glyph_pop.pop_seconds
		speaker.set_process(false)
		speaker.presenter.paused = true
	_game.set_process(false)
	_game._view.set_process(false)
	_game._pipe.process_mode = Node.PROCESS_MODE_DISABLED
	_game._effects.process_mode = Node.PROCESS_MODE_DISABLED
	_game._slime_root.process_mode = Node.PROCESS_MODE_DISABLED
	_tutorial.set_process(false)
	var sizes: Array[Vector2i] = [Vector2i(1280, 800)]
	if both_sizes:
		sizes.append(Vector2i(1920, 1080))
	for resolution: Vector2i in sizes:
		get_tree().root.size = resolution
		await get_tree().process_frame
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		if _compact_dialogue.bubble.visible:
			_check_compact_layout()
		var speaker: Dialogue = _compact_dialogue if _compact_dialogue.visible else _dialogue
		var dialogue_mode: String = "compact" if _compact_dialogue.visible else "large"
		if not speaker.visible:
			dialogue_mode = "hidden"
		var image: Image = get_tree().root.get_texture().get_image()
		var filename: String = "%s_%dx%d.png" % [label, resolution.x, resolution.y]
		_check(image.get_size() == resolution, "The capture uses the requested dimensions.")
		_check(
			image.save_png(_output_directory.path_join(filename)) == OK,
			"Capture saves successfully."
		)
		(
			_captures
			. append(
				{
					"file": filename,
					"captured_at": Time.get_datetime_string_from_system(),
					"phase": Tutorial.Phase.keys()[_tutorial.phase],
					"dialogue_mode": dialogue_mode,
					"dialogue_phase": Dialogue.Phase.keys()[speaker.phase],
					"text": speaker.text_label.get_parsed_text(),
					"visible_characters": speaker.text_label.visible_characters,
					"text_content_height": speaker.text_label.get_content_height(),
					"text_area_height": speaker.text_label.size.y,
					"tree_paused": get_tree().paused,
					"time_scale": Engine.time_scale,
					"width": image.get_width(),
					"height": image.get_height(),
				}
			)
		)
	get_tree().root.size = Vector2i(1280, 800)
	await get_tree().process_frame
	await get_tree().process_frame
	_game.set_process(game_processing)
	_game._view.set_process(view_processing)
	_game._pipe.process_mode = pipe_process_mode
	_game._effects.process_mode = effects_process_mode
	_game._slime_root.process_mode = slimes_process_mode
	_tutorial.set_process(tutorial_processing)
	_dialogue.set_process(dialogue_processing)
	_compact_dialogue.set_process(compact_processing)
	_dialogue.presenter.paused = presenter_paused
	_compact_dialogue.presenter.paused = compact_presenter_paused
	_frozen_transform = _game._world.transform
	_capturing_layout = false


func _prepare_output() -> void:
	_output_directory = ProjectSettings.globalize_path(
		(
			"res://artifacts/tutorial_intro_%d_%d"
			% [int(Time.get_unix_time_from_system()), Time.get_ticks_usec()]
		)
	)
	_check(
		DirAccess.make_dir_recursive_absolute(_output_directory) == OK, "Capture directory exists."
	)


func _on_phase_changed(phase: Tutorial.Phase) -> void:
	if _recording:
		_phases.append(phase)
	if phase == Tutorial.Phase.REACTION:
		_frozen_transform = _game._world.transform
		_frozen_spawn_clocks.clear()
		for nest: NestState in _game.run.nests:
			_frozen_spawn_clocks.append(nest.spawn_clock)
		_frozen_candy = _game.run.candy
		_frozen_capture_count = _capture_count


func _on_line_started(index: int, text: String) -> void:
	if _recording:
		_started_indices.append(index)
		_started_texts.append(text)


func _on_line_finished(index: int) -> void:
	if _recording:
		_finished_indices.append(index)


func _on_completed() -> void:
	_completion_count += 1


func _on_capture_completed(_nest_id: int, candy_gained: int, feedback: CollectionEffect) -> void:
	_capture_count += 1
	_capture_reward += candy_gained
	_last_feedback = feedback
	_check(feedback != null, "A real capture produces a reward feedback instance.")
	if feedback != null:
		feedback.finished.connect(_on_feedback_finished, CONNECT_ONE_SHOT)


func _on_feedback_finished() -> void:
	_feedback_finished_count += 1


func _on_transport_finished() -> void:
	_transport_finished_count += 1


func _on_transport_cancelled() -> void:
	_transport_cancelled_count += 1


func _on_compact_finished() -> void:
	_compact_finished_count += 1


func _check(condition: bool, message: String) -> void:
	if not condition and not _failures.has(message):
		_failures.append(message)
		push_error(message)


func _finish() -> void:
	if _capture_enabled and not _output_directory.is_empty():
		var manifest: FileAccess = FileAccess.open(
			_output_directory.path_join("manifest.json"), FileAccess.WRITE
		)
		if manifest != null:
			(
				manifest
				. store_string(
					(
						(
							JSON
							. stringify(
								{
									"scene": GAME_PATH,
									"captures": _captures,
									"failures": _failures,
									"finished_at": Time.get_datetime_string_from_system(),
								},
								"\t"
							)
						)
						+ "\n"
					)
				)
			)
			manifest.close()
		else:
			_check(false, "Capture manifest saves successfully.")
		print("CAPTURES: ", _output_directory)
	if _failures.is_empty():
		print(
			"PASS: paired nest emergence, simultaneous bursts, actual landing gate, tutorial camera, compact trial layout, real captures and feedback, frozen reaction/closing, smooth resume, early capture, cancellation and restart cleanup."
		)
	else:
		print("FAIL: tutorial checks: ", _failures)
	get_tree().quit(0 if _failures.is_empty() else 1)
