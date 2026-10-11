extends Node

const Demo = preload("res://scripts/disk_demo.gd")
const PREVIEW_MATERIAL: ShaderMaterial = preload(
	"res://features/technology_swirl_preview/swirl_material.tres"
)

@onready var game: Demo = $Game
@onready var backdrop: ColorRect = $Game/HUD/Interface/Technology/Background

var _screen: ShaderMaterial


func _ready() -> void:
	backdrop.set_process(false)
	backdrop.set_process_input(false)
	_screen = PREVIEW_MATERIAL.duplicate() as ShaderMaterial
	backdrop.material = _screen
	game.run.candy = 400
	game.run.economy_changed.emit()
	game._layout._show_technology()
	if "--capture" in OS.get_cmdline_user_args():
		_capture.call_deferred()
	elif "--movie" in OS.get_cmdline_user_args():
		_record.call_deferred()


func _capture() -> void:
	_screen.set_shader_parameter("effect_time", 1.6)
	for resolution in [Vector2i(1280, 800), Vector2i(1920, 1080)]:
		get_window().size = resolution
		await get_tree().create_timer(0.3).timeout
		await _save("technology_swirl_%dx%d" % [resolution.x, resolution.y])
	_screen.set_shader_parameter("effect_time", 4.6)
	await _save("technology_swirl_later")
	print("PASS: Swirl rendered in the existing technology page at two sizes and times.")
	get_tree().quit()


func _save(label: String) -> void:
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var result: Error = get_viewport().get_texture().get_image().save_png(
		"res://artifacts/" + label + ".png"
	)
	assert(result == OK)


func _record() -> void:
	for frame in range(192):
		_screen.set_shader_parameter("effect_time", 1.6 + frame / 24.0)
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
	print("PASS: eight seconds of Swirl animation recorded at 24 FPS.")
	get_tree().quit()
