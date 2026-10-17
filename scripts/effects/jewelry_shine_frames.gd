extends Resource

# Shared, imported masks. The keys are the original animation textures.
@export var masks: Dictionary[Texture2D, Texture2D] = {}
@export var regions: Dictionary[Texture2D, Rect2] = {}
