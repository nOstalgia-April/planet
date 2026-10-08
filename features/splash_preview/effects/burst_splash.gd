extends "res://features/splash_preview/effects/splash_effect_base.gd"

const DropletScript = preload("res://features/splash_preview/effects/splash_droplet.gd")

@onready var _droplets: Array[DropletScript] = [
	$Droplets/Drop01,
	$Droplets/Drop02,
	$Droplets/Drop03,
	$Droplets/Drop04,
	$Droplets/Drop05,
	$Droplets/Drop06,
	$Droplets/Drop07,
	$Droplets/Drop08,
]


func _apply_pose(progress: float) -> void:
	super._apply_pose(progress)
	for droplet in _droplets:
		droplet.show_pose(progress, display_size, intensity, tint)
