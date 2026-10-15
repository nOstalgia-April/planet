extends RichTextEffect

@export_range(0.05, 0.5, 0.01) var pop_seconds: float = 0.18
@export_range(0.0, 24.0, 1.0) var lift_pixels: float = 9.0

var bbcode: String = "dialogue_pop"
var clock: float = 0.0
var revealed_at: PackedFloat32Array = PackedFloat32Array()


func _process_custom_fx(char_fx: CharFXTransform) -> bool:
	var index: int = char_fx.range.x
	if index >= revealed_at.size():
		char_fx.visible = false
		return true
	var progress: float = clampf((clock - revealed_at[index]) / pop_seconds, 0.0, 1.0)
	char_fx.offset.y += -sin(progress * PI) * lift_pixels
	char_fx.color.a *= clampf(progress * 3.0, 0.0, 1.0)
	return true
