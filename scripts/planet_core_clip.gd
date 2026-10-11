class_name PlanetCoreClip
extends Resource

## Paths intentionally avoid preloading every atlas into video memory.
@export var page_paths: PackedStringArray = []
@export var frame_tiles: PackedInt32Array = []
@export var tile_size: Vector2i = Vector2i(356, 300)
@export var columns: int = 8
@export var rows: int = 8
@export var pivot: Vector2 = Vector2(180, 171)
