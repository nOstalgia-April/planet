extends Node


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var arguments: PackedStringArray = OS.get_cmdline_user_args()
	var mode: String = arguments[0] if not arguments.is_empty() else "gameplay"
	var path: String = "res://scenes/disk_demo.tscn"
	if mode == "menu":
		path = "res://scenes/主菜单/主菜单.tscn"
	elif mode == "opening":
		path = "res://scenes/开头动画/开头动画.tscn"
	var packed: PackedScene = load(path) as PackedScene
	var scene: Node = packed.instantiate()
	get_tree().root.add_child(scene)
	get_tree().current_scene = scene
	# Keep preload in flight for the immediate menu/window-close case.
	if mode == "gameplay":
		await get_tree().create_timer(1.0).timeout
	else:
		await get_tree().process_frame
	packed = null
	print("CHECK: window close during " + mode)
	get_tree().root.close_requested.emit()
	# A second close request must not start another cleanup coroutine.
	get_tree().root.close_requested.emit()
