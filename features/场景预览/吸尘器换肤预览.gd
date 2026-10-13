extends "res://features/场景预览/动作预览.gd"

const VacuumSkin = preload("res://scripts/vacuum_skin.gd")


func _select_skin(skin: int) -> void:
	(view as VacuumSkin).request_skin(skin as VacuumSkin.SkinKind)
