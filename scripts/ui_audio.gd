extends Node

# Autoload "UiAudio": gives every button in every scene hover and click sounds.
# Purchase buttons are registered separately: a successful purchase plays
# Level Up from game code, and clicking one that is disabled for lack of candy
# plays Insufficient Point. The tool dock's buttons and keys 1/2 play their own
# switch sounds instead of Click.

const CLICK_EVENT: String = "event:/UI/Button_Click"
const HOVER_EVENT: String = "event:/UI/Button_Hover"
const INSUFFICIENT_EVENT: String = "event:/UI/Button_InsufPoint"
const LEVEL_UP_EVENT: String = "event:/UI/Button_Levelup"
const SWITCH_VACUUM_EVENT: String = "event:/UI/Switch-Vacuum"
const SWITCH_NET_EVENT: String = "event:/UI/Switch-Net"
const HOOKED_META: StringName = &"ui_audio_hooked"
const PURCHASE_META: StringName = &"ui_audio_purchase"
# Buttons whose press sound comes from game code rather than Click.
const OWN_SOUND_META: StringName = &"ui_audio_own_sound"

var _ready_to_play: bool = false
var _switch_ready: bool = false


func _ready() -> void:
	_ready_to_play = GameAudio.has_events(
		[CLICK_EVENT, HOVER_EVENT, INSUFFICIENT_EVENT, LEVEL_UP_EVENT]
	)
	_switch_ready = GameAudio.has_events([SWITCH_VACUUM_EVENT, SWITCH_NET_EVENT])
	if not _ready_to_play:
		return
	get_tree().node_added.connect(_on_node_added)
	_hook_tree(get_tree().root)


func is_ready() -> bool:
	return _ready_to_play


func level_up() -> void:
	if _ready_to_play:
		GameAudio.play(LEVEL_UP_EVENT)


func insufficient_points() -> void:
	if _ready_to_play:
		GameAudio.play(INSUFFICIENT_EVENT)


func click() -> void:
	if _ready_to_play:
		GameAudio.play_now(CLICK_EVENT)


# net: switched to the net, otherwise to the vacuum.
func tool_switched(net: bool) -> void:
	if _switch_ready:
		GameAudio.play_now(SWITCH_NET_EVENT if net else SWITCH_VACUUM_EVENT)


# The button keeps its hover sound but no longer plays Click on press.
func register_own_sound(button: BaseButton) -> void:
	button.set_meta(OWN_SOUND_META, true)


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
	# button_down fires on the press itself, before any pressed handler can
	# start a blocking scene change.
	button.button_down.connect(_on_button_down.bind(button))


func _on_hover(button: BaseButton) -> void:
	if not button.disabled:
		GameAudio.play(HOVER_EVENT)


func _on_button_down(button: BaseButton) -> void:
	if not button.has_meta(PURCHASE_META) and not button.has_meta(OWN_SOUND_META):
		GameAudio.play_now(CLICK_EVENT)


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
