extends "res://features/场景预览/动作预览.gd"

const VacuumSkin = preload("res://scripts/vacuum_skin.gd")


func _select_skin(skin: int) -> void:
	var art: VacuumSkin = view as VacuumSkin
	if skin == VacuumSkin.SkinKind.DEFAULT:
		art.reset_skin()
		return
	art.notify_capture()
	art.request_skin(skin as VacuumSkin.SkinKind)
