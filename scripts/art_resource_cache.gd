extends RefCounted


# SceneTree owns these memoized resources and drops them before renderer shutdown.
# Script statics outlive that shutdown in Godot 4.7.2, even with @static_unload.
static func get_cache(key: StringName) -> Dictionary:
	var registry: Dictionary = _registry()
	if not registry.has(key):
		registry[key] = {}
	return registry[key]


static func texture_bounds(key: StringName) -> Dictionary[Texture2D, Rect2]:
	var registry: Dictionary = _registry()
	if not registry.has(key):
		var cache: Dictionary[Texture2D, Rect2] = {}
		registry[key] = cache
	return registry[key]


static func texture_feet() -> Dictionary[Texture2D, ImageTexture]:
	var registry: Dictionary = _registry()
	if not registry.has(&"planet_nest_texture_feet"):
		var cache: Dictionary[Texture2D, ImageTexture] = {}
		registry[&"planet_nest_texture_feet"] = cache
	return registry[&"planet_nest_texture_feet"]


static func alpha_masks() -> Dictionary[Texture2D, BitMap]:
	var registry: Dictionary = _registry()
	if not registry.has(&"planet_mucus_alpha_masks"):
		var cache: Dictionary[Texture2D, BitMap] = {}
		registry[&"planet_mucus_alpha_masks"] = cache
	return registry[&"planet_mucus_alpha_masks"]


static func _registry() -> Dictionary:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if not tree.has_meta(&"planet_art_resource_cache"):
		var registry: Dictionary = {}
		tree.set_meta(&"planet_art_resource_cache", registry)
		tree.root.tree_exiting.connect(_release.bind(registry), CONNECT_ONE_SHOT)
	return tree.get_meta(&"planet_art_resource_cache")


static func _release(registry: Dictionary) -> void:
	for cache: Dictionary in registry.values():
		cache.clear()
	registry.clear()
