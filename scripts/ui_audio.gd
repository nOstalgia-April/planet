extends Node

# Autoload "UiAudio": gives every button in every scene hover and click sounds.
# Purchase buttons are registered separately: a successful purchase plays
# Level Up from game code, and clicking one that is disabled for lack of candy
# plays Insufficient Point.

const CLICK_EVENT: String = "event:/UI/Button_Click"
const HOVER_EVENT: String = "event:/UI/Button_Hover"
const INSUFFICIENT_EVENT: String = "event:/UI/Button_InsufPoint"
const LEVEL_UP_EVENT: String = "event:/UI/Button_Levelup"
const HOOKED_META: StringName = &"ui_audio_hooked"
const PURCHASE_META: StringName = &"ui_audio_purchase"

var _ready_to_play: bool = false


func _ready() -> void:
	_ready_to_play = GameAudio.has_events(
		[CLICK_EVENT, HOVER_EVENT, INSUFFICIENT_EVENT, LEVEL_UP_EVENT]
	)
	if not _ready_to_play:
		return
	get_tree().node_added.connect(_on_node_added)
	_hook_tree(get_tree().root)


func is_ready() -> bool:
	return _ready_to_play


func level_up() -> void:
	if _ready_to_play:
		GameAudio.play(LEVEL_UP_EVENT)


# is_unaffordable: returns true when the button is disabled only for lack of candy.
func register_purchase(button: BaseButton, is_unaffordable: Callable) -> void:
	button.set_meta(PURCHASE_META, true)
	button.gui_input.connect(_on_purchase_input.bind(button, is_unaffordable))


func _hook_tree(node: Node) -> void:
	_on_node_added(node)
	for child: Node in node.get_children():
		_hook_tree(child)


func _on_node_added(node: Node) -> void:
	if not node is BaseButton or node.has_meta(HOOKED_META):
		return
	var button: BaseButton = node as BaseButton
	button.set_meta(HOOKED_META, true)
	button.mouse_entered.connect(_on_hover.bind(button))
	button.pressed.connect(_on_pressed.bind(button))


func _on_hover(button: BaseButton) -> void:
	if not button.disabled:
		GameAudio.play(HOVER_EVENT)


func _on_pressed(button: BaseButton) -> void:
	if not button.has_meta(PURCHASE_META):
		GameAudio.play(CLICK_EVENT)


func _on_purchase_input(event: InputEvent, button: BaseButton, is_unaffordable: Callable) -> void:
	var click: InputEventMouseButton = event as InputEventMouseButton
	if (
		click != null
		and click.pressed
		and click.button_index == MOUSE_BUTTON_LEFT
		and button.disabled
		and is_unaffordable.call()
	):
		GameAudio.play(INSUFFICIENT_EVENT)
