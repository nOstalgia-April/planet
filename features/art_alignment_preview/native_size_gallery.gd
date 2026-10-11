extends PanelContainer

var _nests: Array[NestView] = []
var _monsters: Array[PrototypeSlime] = []
var _indices: Array[int] = []
var _pictures: Array[TextureRect] = []
var _labels: Array[Label] = []

@onready var _items: HBoxContainer = $Scroll/Items


func configure(nests: Array[NestView], monsters: Array[PrototypeSlime], target: int) -> void:
	_nests = nests
	_monsters = monsters
	_indices.clear()
	if target == 0:
		_indices.assign([0, 1, 2, 3, 4, 5])
	elif target == 1:
		_indices.assign([0, 1, 2])
	elif target == 2:
		_indices.assign([3, 4, 5])
	elif target < 15:
		_indices.append((target - 3) / 4)
	else:
		_indices.append(target - 15 + 3)
	for child: Node in _items.get_children():
		_items.remove_child(child)
		child.queue_free()
	_pictures.clear()
	_labels.clear()
	for index: int in _indices:
		var column: VBoxContainer = VBoxContainer.new()
		_items.add_child(column)
		var label: Label = Label.new()
		label.add_theme_font_size_override("font_size", 16)
		column.add_child(label)
		_labels.append(label)
		var picture: TextureRect = TextureRect.new()
		picture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		picture.stretch_mode = TextureRect.STRETCH_KEEP
		picture.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		picture.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		column.add_child(picture)
		_pictures.append(picture)
	_update_textures()


func _process(_delta: float) -> void:
	if is_visible_in_tree():
		_update_textures()


func _update_textures() -> void:
	const NAMES: Array[String] = ["史莱姆巢穴", "黏液巢穴", "地鼠巢穴", "史莱姆", "黏液怪", "地鼠"]
	for slot: int in range(_indices.size()):
		var index: int = _indices[slot]
		var texture: Texture2D = (
			_nests[index].get_source_texture()
			if index < 3
			else _monsters[index - 3].get_source_texture()
		)
		_pictures[slot].texture = texture
		_labels[slot].text = (
			"%s · %d × %d px · 100%%" % [NAMES[index], texture.get_width(), texture.get_height()]
		)
