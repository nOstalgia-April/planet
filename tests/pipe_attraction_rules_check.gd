extends SceneTree

const SETTINGS: PrototypeSettings = preload("res://resources/prototype_settings.tres")

var _failures: Array[String] = []


func _initialize() -> void:
	_run_checks.call_deferred()


func _run_checks() -> void:
	var run: PrototypeRun = PrototypeRun.new()
	run.settings = SETTINGS
	root.add_child(run)
	run.start_run(_positions())
	for property: Dictionary in SETTINGS.get_property_list():
		_check(
			not String(property["name"]) in ["pipe_attraction_radius", "pipe_attraction_speed"],
			"Removed peripheral attraction exposes no gameplay configuration."
		)
	run.candy = 10000
	_check(
		(
			run.get_technology_level("attraction") == -1
			and run.get_technology_cost("attraction") == -1
			and run.get_technology_description("attraction").is_empty()
			and not run.purchase_technology("attraction")
			and run.candy == 10000
		),
		"The removed attraction technology cannot be bought or charge candy."
	)
	while run.get_pipe_upgrade_cost() >= 0:
		_check(run.upgrade_pipe(), "Pipe speed upgrades remain independently purchasable.")
	run.upgrade_net()
	run.upgrade_net()
	_check(
		(
			is_equal_approx(run.get_pipe_capture_seconds(), 0.11)
			and run.get_net_capacity() == 10
			and is_equal_approx(run.get_pipe_radius(), 9.6)
		),
		"Pipe speed and net capacity upgrades preserve the 9.6-unit processing center."
	)
	run.start_run(_positions())
	_check(
		(
			is_equal_approx(run.get_pipe_radius(), 9.6)
			and is_equal_approx(run.get_pipe_capture_seconds(), 0.6)
			and run.pipe_level == 0
			and not run.net_unlocked
			and run.candy == 0
		),
		"Restart preserves the processing center while clearing tool upgrades and economy."
	)
	run.free()
	if _failures.is_empty():
		print("PASS: no peripheral attraction settings or research, independent tools and restart")
	else:
		for failure: String in _failures:
			push_error(failure)
	quit(0 if _failures.is_empty() else 1)


func _positions() -> Array[Vector2]:
	return [Vector2(-50, -200), Vector2(50, -200), Vector2(190, -60)]


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
