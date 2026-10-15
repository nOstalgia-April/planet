extends Node

const SharedCache = preload("res://scripts/art_resource_cache.gd")
const BodyCache = preload("res://scripts/slime_body_cache.gd")
const Page = preload("res://scripts/ui/interactive_technology_page.gd")
const PageScene: PackedScene = preload("res://scenes/ui/interactive_technology_page.tscn")


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var body: Texture2D = BodyCache.get_body_texture(4.0, false, Color.GREEN, Color.BLACK)
	assert(body == BodyCache.get_body_texture(4.0, false, Color.GREEN, Color.BLACK))
	var first: Page = PageScene.instantiate() as Page
	add_child(first)
	first.set_zoom(0.7)
	first.set_view_center(Vector2(400.0, 450.0))
	first.free()
	var second: Page = PageScene.instantiate() as Page
	add_child(second)
	assert(is_equal_approx(second.zoom_factor, 0.7))
	assert(second.view_center == Vector2(400.0, 450.0))
	second.free()
	assert(not SharedCache.get_cache(&"planet_slime_bodies").is_empty())
	print("PASS: shared procedural texture reuse and technology view memory after recreation.")
	get_tree().quit.call_deferred()
