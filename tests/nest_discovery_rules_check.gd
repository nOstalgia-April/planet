extends "res://tests/progressive_rules_check.gd"


func _run_checks() -> void:
	_check_opening_and_net_unlock()
	_check_nest_opening_delay()
	_check_continuous_discovery()
	_check_nest_discovery_cooldown()
	_check_governance_roll_weight()
	_check_existing_nests_completion()
	if _failures.is_empty():
		print(
			"PASS: opening protection, net unlock, discovery probability, success cooldown and reset"
		)
	else:
		for failure: String in _failures:
			push_error(failure)
	quit(0 if _failures.is_empty() else 1)
