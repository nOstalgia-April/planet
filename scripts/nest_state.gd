class_name NestState
extends RefCounted

var nest_id: int = 0
var level: int = 0
var position: Vector2 = Vector2.ZERO
# Current living population on the planet surface.
var alive_slimes: int = 0
var spawn_clock: float = 0.0
var is_tamed: bool = false
