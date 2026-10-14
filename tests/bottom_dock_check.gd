extends Node

const PLAY: PackedScene = preload("res://features/场景预览/近景游玩预览.tscn")
const Play = preload("res://features/场景预览/游玩预览.gd")
const Dock = preload("res://scripts/ui/bottom_dock.gd")
const OUTPUT: String = "res://artifacts/dock_net_size_20261014"

var _failures: int = 0
var _game: Play
var _dock: Dock


func _ready() -> void:
	get_tree().root.set_flag(Window.FLAG_MOUSE_PASSTHROUGH, true)
	_check_game.call_deferred()


func _check_game() -> void:
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	_game = PLAY.instantiate() as Play
	add_child(_game)
	await _settle()
	_game.set_process(false)
	_dock = _game._layout._tool_dock
	await _hover(Vector2(5, 120))
	_check(_dock.pipe_button.visible and _dock.technology_button.visible, "permanent entries")
	_check(not _dock.net_button.is_visible_in_tree(), "net hidden before discovery")
	_check(
		not (_dock.pipe_button.get_node("Status") as Label).visible,
		"opening tool has no upgrade progress"
	)
	await _hover(_dock.pipe_button.get_global_rect().get_center())
	_check(
		_dock._expanded[0] and _dock.upgrades[0].disabled, "unaffordable hover previews next level"
	)
	await _capture("unaffordable_hover")
	await _click(_dock.upgrades[0])
	_check(
		_game.run.pipe_level == 0 and _game.run.candy == 0, "unaffordable preview cannot purchase"
	)
	await _hover(Vector2(5, 120))
	_check(not _dock._expanded[0], "unaffordable preview retracts after leaving")
	await _capture("opening")
	await _wallet(_game.run.get_technology_cost("pipe"))
	_check(_dock._expanded[0], "first affordable speed upgrade announces itself")
	_check(
		(
			(_dock.pipe_button.get_node("Detail") as Label).position.y == 19.0
			and (_dock.pipe_button.get_node("Status") as Label).visible
		),
		"available upgrade lifts level into a two-line layout"
	)
	_check(not _dock.badge.visible, "owned speed technology never triggers discovery badge")
	_game._layout._toggle_pause()
	await _settle()
	_check(
		not _dock.can_process() and not _dock.upgrades[0].visible,
		"pause blocks tools and immediately hides purchases"
	)
	_game._layout._toggle_pause()
	await _settle()
	_check(_dock._expanded[0], "unseen announcement returns after pause")
	await _hover(_dock.pipe_button.get_global_rect().get_center())
	await _hover(_dock.upgrades[0].get_global_rect().get_center())
	_check(_dock._expanded[0], "moving from tool to purchase keeps it open")
	await _hover(Vector2(5, 120))
	_check(_dock._expanded[0], "affordable upgrade remains after leaving")
	await _wallet(0)
	await _wallet(_game.run.get_technology_cost("pipe"))
	_check(_dock._expanded[0], "wallet refill restores affordable upgrade")
	await _hover(_dock.pipe_button.get_global_rect().get_center())
	_check(_dock._expanded[0], "hover reopens an acknowledged upgrade")
	await _click(_dock.upgrades[0])
	_check(_game.run.pipe_level == 1, "speed button purchases real upgrade")
	_check(
		(_dock.pipe_button.get_node("Detail") as Label).text == "2 级",
		"shortcut shows purchased level"
	)
	_check(
		_dock.pipe_button.tooltip_text.is_empty(), "shortcut does not duplicate detailed statistics"
	)
	await _hover(Vector2(5, 120))
	await _wallet(100)
	_check(_dock.net_button.is_visible_in_tree(), "affordable unlock discovers net")
	_check(
		_dock._expanded[1] and _dock.states[1] == Dock.ToolState.LOCKED_READY,
		"locked net announces orange unlock"
	)
	_check(_dock.badge.visible, "never unlocked technology triggers badge")
	await _capture("unlock_available")
	await _wallet(0)
	_check(_dock.net_button.is_visible_in_tree(), "discovered net remains after wallet drops")
	_check(_dock.states[1] == Dock.ToolState.LOCKED_SHORT, "locked net enters insufficient state")
	_check(not _dock._expanded[1], "unaffordable purchase retracts")
	_check(
		(
			not (_dock.net_button.get_node("Status") as Label).visible
			and (_dock.net_button.get_node("Detail") as Label).position.y == 28.0
		),
		"unaffordable tool has one centered line"
	)
	await _hover(_dock.net_button.get_global_rect().get_center())
	_check(
		_dock._expanded[1] and _dock.upgrades[1].disabled,
		"discovered locked net previews its cost without funds"
	)
	await _capture("insufficient_hover")
	await _hover(Vector2(5, 120))
	await _capture("insufficient")
	await _wallet(100)
	_check(_dock._expanded[1], "affordable unlock remains available on wallet refill")
	await _hover(_dock.net_button.get_global_rect().get_center())
	await _click(_dock.upgrades[1])
	_check(_game.run.net_unlocked, "unlock button unlocks real tool")
	_check(
		(
			(_dock.upgrades[1].get_node("Caption/Level") as Label).text == "捕网扩容 ·"
			and (_dock.upgrades[1].get_node("Caption/Cost") as Label).text == "50"
			and (_dock.upgrades[1].get_node("Caption/Coin") as TextureRect).texture != null
		),
		"purchase names upgrade direction and cost"
	)
	await _click(_dock.net_button)
	_check(_game._active_tool == 1, "unlocked net can be selected")
	_check(
		(
			(_dock.net_button.get_node("Selected") as Dock.Selection).selected
			and not (_dock.pipe_button.get_node("Selected") as Dock.Selection).selected
		),
		"selection border follows the active tool"
	)
	var selection: Dock.Selection = _dock.net_button.get_node("Selected") as Dock.Selection
	selection.set_selected(false)
	await _settle()
	selection.set_selected(true)
	await get_tree().create_timer(0.08, true).timeout
	_check(selection._reveal > 0.0 and selection._reveal < 1.0, "selection paints progressively")
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OUTPUT + "/selection_transition.png")
	await _settle()
	_check(is_equal_approx(selection._reveal, 1.0), "selection settles into a complete border")
	await _check_cooldown_shortcuts()
	var before_capacity: int = _game.run.get_net_capacity()
	await _click(_dock.upgrades[1])
	_check(_game.run.get_net_capacity() > before_capacity, "capacity button upgrades real capacity")
	_check(
		(_dock.net_button.get_node("Detail") as Label).text == "2 级",
		"net shortcut shows purchased level"
	)
	await _wallet(10000)
	await _click(_dock.upgrades[0])
	await _hover(Vector2(5, 120))
	_check(_dock._expanded[0], "successive affordable level remains visible after purchase")
	await _hover(Vector2(5, 120))
	await _hover(_dock.pipe_button.get_global_rect().get_center())
	await _capture("owned")
	_check(
		(
			float(
				(
					(_dock.pipe_button.get_node("Backing").material as ShaderMaterial)
					. get_shader_parameter("hover_amount")
				)
			)
			== 1.0
		),
		"hover lights only the pointed tool"
	)
	await _hover(Vector2(5, 120))
	await _capture("idle_owned")
	for surface: Button in _dock.surfaces:
		_check(
			(
				float(
					(surface.get_node("Backing").material as ShaderMaterial).get_shader_parameter(
						"hover_amount"
					)
				)
				== 0.0
			),
			"leaving clears white glow independently of selection"
		)
	_check(
		(_dock.net_button.get_node("Selected") as Dock.Selection).selected,
		"selection survives hover leaving"
	)
	await _hover(_dock.technology_button.get_global_rect().get_center())
	await _capture("technology_hover")
	_check(
		(
			float(
				(
					(_dock.technology_button.get_node("Backing").material as ShaderMaterial)
					. get_shader_parameter("hover_amount")
				)
			)
			== 1.0
		),
		"technology has its own hover glow"
	)
	await _hover(_dock.pipe_button.get_global_rect().get_center())
	await _hover(_dock.upgrades[0].get_global_rect().get_center())
	await _capture("purchase_hover")
	_check(
		(
			float(
				(
					(_dock.pipe_button.get_node("Backing").material as ShaderMaterial)
					. get_shader_parameter("hover_amount")
				)
			)
			== 0.0
		),
		"purchase hover does not light the underlying tool"
	)
	await _hover(_dock.net_button.get_global_rect().get_center())
	await _capture("capacity_upgrade")
	_game._population_palette.set_process(false)
	for species: int in [1, 2]:
		var counts: Vector3 = Vector3.ZERO
		counts[species] = 100.0
		_game._population_palette.advance_population(counts, 3.0)
		await _capture("palette_%d" % species)
	var material: ShaderMaterial = _dock.upgrades[0].get_node("Backing").material as ShaderMaterial
	_check(
		(material.get_shader_parameter("accent") as Color).is_equal_approx(
			_game._population_palette.settings.green[1]
		),
		"upgrade follows population palette"
	)
	_game._layout._show_technology()
	await _settle()
	_check(
		not _dock._expanded[0] and not _dock._expanded[1], "technology page suppresses dock popups"
	)
	_game._layout.close_panels()
	await _settle()
	for id: String in ["cultivation", "automation", "valuable", "giant", "combo_unlock"]:
		_game.run.purchase_technology(id)
	await _settle()
	_check(not _dock.badge.visible, "remaining repeatable upgrades do not trigger discovery badge")
	await _wallet(1000000)
	while _game.run.purchase_technology("net_capacity"):
		pass
	await _settle()
	await _check_size_upgrades()
	await _wallet(1000000)
	_game._select_nest(1)
	await _capture("nest_wild")
	_game.run.upgrade_nest(1)
	_game.run.upgrade_nest(1)
	_game._select_nest(1)
	_check(_game._nest_level_label.text == "强化培育", "nest shortcut shows cultivation stage")
	await _capture("nest_automation_next")
	_game.run.upgrade_nest(1)
	_game._select_nest(1)
	_check(_game._nest_level_label.text == "完全治理", "nest shortcut shows final stage")
	await _capture("nest_automated")
	_game._layout.hide_nest_details()
	while _game.run.purchase_technology("pipe"):
		pass
	await _settle()
	_check(
		_dock.states[0] == Dock.ToolState.MAXED and _dock.states[1] == Dock.ToolState.MAXED,
		"maxed tools have explicit state"
	)
	await _hover(_dock.pipe_button.get_global_rect().get_center())
	_check(not _dock._expanded[0], "maxed tool never exposes purchase")
	await _capture("maxed")
	_game.restart_run()
	await _settle()
	_check(_game.run.get_net_quick_upgrade_id() == "net_unlock" and _game.run.net_size_level == 0, "restart restores net shortcut progression")
	_check(
		not _dock.net_discovered and not _dock.net_button.is_visible_in_tree(),
		"restart resets net discovery"
	)
	await _wallet(_game.run.get_technology_cost("pipe"))
	_check(_dock._expanded[0], "new run can announce the same first upgrade")
	_game.queue_free()
	await get_tree().process_frame
	print("Bottom dock: %d failures" % _failures)
	get_tree().quit(0 if _failures == 0 else 1)


func _check_size_upgrades() -> void:
	_check(_dock.states[1] == Dock.ToolState.READY and _dock._expanded[1], "capacity max opens affordable size shortcut")
	_check((_dock.net_button.get_node("Detail") as Label).text == "大小 1 级", "shortcut distinguishes size from capacity")
	for index: int in range(3):
		var cost: int = [1500, 3000, 5000][index]
		_check((_dock.upgrades[1].get_node("Caption/Level") as Label).text == "捕网大小 ·", "shortcut identifies size without the next level")
		_check((_dock.upgrades[1].get_node("Caption/Cost") as Label).text == str(cost), "shortcut displays the size price")
		await _wallet(cost - 1)
		await _hover(_dock.net_button.get_global_rect().get_center())
		_check(_dock.upgrades[1].disabled, "size shortcut disables when one candy short")
		await _click(_dock.upgrades[1])
		_check(_game.run.net_size_level == index and _game.run.candy == cost - 1, "unaffordable size shortcut cannot spend")
		await _hover(Vector2(5, 120))
		_check(not _dock._expanded[1], "unaffordable size preview closes on leaving")
		await _wallet(cost)
		_check(_dock._expanded[1] and not _dock.upgrades[1].disabled, "exact size price opens shortcut without hover")
		await _capture("size_%d_available" % (index + 2))
		var caption: Control = _dock.upgrades[1].get_node("Caption") as Control
		_check(_dock.upgrades[1].get_global_rect().encloses(caption.get_global_rect()), "size label and price fit the purchase tab")
		await _click(_dock.upgrades[1])
		_check(_game.run.net_size_level == index + 1 and _game.run.candy == 0, "size shortcut buys and charges exactly once")
		_check(_game.run.get_net_capacity() == 30 and is_equal_approx(_game.run.get_net_radius(), [42.0, 50.4, 58.8][index]), "shortcut grows radius while preserving capacity")
		_check((_dock.net_button.get_node("Detail") as Label).text == "大小 %d 级" % (index + 2), "size shortcut shows the purchased level")
	_check(_dock.states[1] == Dock.ToolState.MAXED and not _dock._expanded[1], "size max stops shortcut announcements")
	await _hover(_dock.net_button.get_global_rect().get_center())
	_check(not _dock._expanded[1], "size max stays closed on hover")
	await _wallet(10000)
	_game._on_quick_upgrade(1)
	_check(_game.run.candy == 10000 and _game.run.net_size_level == 3, "maxed shortcut cannot charge again")


func _check_cooldown_shortcuts() -> void:
	await _click(_dock.shortcuts[0])
	_check(_game._active_tool == 0, "clicking 1 selects vacuum")
	_check(_game.run.begin_net_cast(), "net cooldown starts through the model")
	_dock.refresh_timers(_game.run)
	await _hover(Vector2(5, 120))
	await _capture("cooldown_empty")
	_game.run.advance(_game.run.settings.net_cooldown_seconds * 0.5)
	_dock.refresh_timers(_game.run)
	await _capture("cooldown_half")
	_check(
		_dock.net_cooldown.visible and _game._active_tool == 0,
		"net cooldown remains visible while vacuum is selected"
	)
	await _click(_dock.shortcuts[1])
	_check(_game._active_tool == 1, "clicking 2 selects net during cooldown")
	_check(not _game.run.can_cast_net(), "switching tools preserves cooldown")
	_game._layout._toggle_pause()
	var remaining: float = _game.run.net_cooldown_remaining
	await _settle()
	_check(
		(
			is_equal_approx(_game.run.net_cooldown_remaining, remaining)
			and not _dock.net_cooldown.can_process()
		),
		"pause freezes cooldown and feedback"
	)
	_game._layout._toggle_pause()
	_game.run.advance(remaining)
	_dock.refresh_timers(_game.run)
	await get_tree().create_timer(0.1).timeout
	_check(_dock.net_cooldown.visible, "ready transition flashes")
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OUTPUT + "/ready_flash.png")
	await get_tree().create_timer(0.7).timeout
	_check(not _dock.net_cooldown.visible, "ready flash ends without repeating")
	_dock.refresh_timers(_game.run)
	_check(not _dock.net_cooldown.visible, "idle refresh does not restart flashing")
	for key: Key in [KEY_1, KEY_2]:
		var event: InputEventKey = InputEventKey.new()
		event.keycode = key
		event.pressed = true
		get_tree().root.push_input(event, true)
		await get_tree().process_frame
		_check(_game._active_tool == (0 if key == KEY_1 else 1), "number keys switch tools")
	_game.run.begin_net_cast()
	_dock.refresh_timers(_game.run)
	_dock.reset_notifications()
	_check(not _dock.net_cooldown.visible, "reset removes pending cooldown feedback")
	_game.run.net_cooldown_remaining = 0.0
	_dock.refresh(_game.run)


func _wallet(amount: int) -> void:
	_game.run.candy = amount
	_game.run.economy_changed.emit()
	await _settle()


func _hover(point: Vector2) -> void:
	var event: InputEventMouseMotion = InputEventMouseMotion.new()
	event.position = point
	event.global_position = point
	get_tree().root.push_input(event, true)
	await _settle()


func _click(button: Control) -> void:
	await _hover(button.get_global_rect().get_center())
	for pressed: bool in [true, false]:
		var event: InputEventMouseButton = InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = button.get_global_rect().get_center()
		event.global_position = event.position
		get_tree().root.push_input(event, true)
		await get_tree().process_frame
	await _settle()


func _capture(label: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var hovered_surface: int = -1
	for index: int in range(_dock.surfaces.size()):
		var surface: Button = _dock.surfaces[index]
		if (
			surface.is_visible_in_tree()
			and surface.get_global_rect().has_point(_dock._pointer_position)
		):
			hovered_surface = index
	for resolution: Vector2i in [Vector2i(1280, 800), Vector2i(1920, 1080)]:
		get_tree().root.size = resolution
		await _settle()
		if hovered_surface >= 0:
			if hovered_surface >= 3 and hovered_surface <= 4:
				await _hover(_dock.buttons[hovered_surface - 3].get_global_rect().get_center())
			await _hover(_dock.surfaces[hovered_surface].get_global_rect().get_center())
		if label.begins_with("nest_"):
			_game._select_nest(1)
			await _settle()
		await RenderingServer.frame_post_draw
		var path: String = OUTPUT + "/%s_%dx%d.png" % [label, resolution.x, resolution.y]
		_check(get_viewport().get_texture().get_image().save_png(path) == OK, "capture " + label)


func _settle() -> void:
	await get_tree().process_frame
	await get_tree().create_timer(0.4, true).timeout


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)
