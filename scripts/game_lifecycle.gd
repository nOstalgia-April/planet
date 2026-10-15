extends Node

var quitting: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().auto_accept_quit = false
	get_tree().root.close_requested.connect(request_quit)


func request_quit() -> void:
	if quitting:
		return
	quitting = true
	var tree: SceneTree = get_tree()
	var scene: Node = tree.current_scene
	tree.current_scene = null
	if scene != null:
		scene.queue_free()
	# Scene exit retrieves pending loads. Allow their deferred native deletions
	# to drain while the message queue, renderer and audio system still exist.
	await tree.process_frame
	await tree.process_frame
	tree.quit.call_deferred()
