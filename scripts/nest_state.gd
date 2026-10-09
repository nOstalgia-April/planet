class_name NestState
extends RefCounted

enum Species { SLIME, MUCUS }

var nest_id: int = 0
var species: Species = Species.SLIME
var level: int = 0
var valuable_level: int = 0
var position: Vector2 = Vector2.ZERO
# Current living population on the planet surface.
var alive_slimes: int = 0
var spawn_clock: float = 0.0
var income_remainder: float = 0.0
var is_tamed: bool = false
