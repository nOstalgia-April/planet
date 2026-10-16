extends "res://scripts/ui/bottom_dock.gd"

const ART_PINK: Color = Color("ff2891")


func _update_accent(index: int) -> void:
	# This skin uses the artist's fixed pink, independently of the planet palette.
	(buttons[index].get_node("Selected") as Selection).self_modulate = ART_PINK
	if index == 1:
		net_cooldown.set_accent(ART_PINK)


func _update_surface_hover(delta: float) -> void:
	super._update_surface_hover(delta)
	var backing: ShaderMaterial = technology_button.get_node("Backing").material as ShaderMaterial
	var planet: TextureRect = technology_button.get_node("Planet") as TextureRect
	(planet.material as ShaderMaterial).set_shader_parameter(
		"hover_amount", backing.get_shader_parameter("hover_amount")
	)
	var amount: float = backing.get_shader_parameter("hover_amount")
	(technology_button.get_node("Caption") as Label).modulate = Color.BLACK.lerp(
		Color.WHITE, amount
	)
