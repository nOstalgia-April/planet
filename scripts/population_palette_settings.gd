extends Resource

# Fixed 4:2:1 tier-two reference: slime 1/2; drill sqrt(30 * 24) ~= 27.
# Extra nests keep their advantage; never normalize by the current nest mix.
@export var population_weights: Vector3 = Vector3(0.5, 1.0, 27.0)
@export_range(0.0, 0.5, 0.01) var lead_margin: float = 0.05
@export_range(0.0, 5.0, 0.1) var confirmation_seconds: float = 1.2
@export_range(0.1, 5.0, 0.1) var transition_seconds: float = 1.0
@export var pink: PackedColorArray = PackedColorArray(
	[Color("45091e"), Color("881e35"), Color("c21f57"), Color("d32e5e"), Color("f6cad6")]
)
@export var blue: PackedColorArray = PackedColorArray(
	[Color("0e113c"), Color("192c74"), Color("284ec9"), Color("2254ff"), Color("b8d0f7")]
)
@export var green: PackedColorArray = PackedColorArray(
	[Color("032300"), Color("004e22"), Color("217900"), Color("298b00"), Color("c0dbac")]
)


func colors_for(species: int) -> PackedColorArray:
	match species:
		NestState.Species.MUCUS:
			return blue
		NestState.Species.DRILL:
			return green
	return pink
