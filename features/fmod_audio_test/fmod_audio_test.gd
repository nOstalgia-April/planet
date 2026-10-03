extends Control

const BANK_ROOT: String = "res://assets/fmod/banks"
const BANK_NAMES: PackedStringArray = ["Master.strings.bank", "Master.bank", "SFX.bank"]
const COLLECT_EVENT: String = "event:/Slime/Collect"
const SUCTION_EVENT: String = "event:/Tools/Suction"
const OUTPUT_TEST_FILE: String = "res://assets/audio/collect.wav"

var _bank_loader: FmodBankLoader
var _banks_ready: bool = false
var _collect_ready: bool = false
var _suction_ready: bool = false
var _progress_ready: bool = false
var _suction_active: bool = false
var _output_file: FmodFile
var _output_sound: FmodSound

@onready var _bank_host: Node = $BankHost
@onready var _collect_emitter: FmodEventEmitter2D = $CollectEmitter
@onready var _suction_emitter: FmodEventEmitter2D = $SuctionEmitter
@onready var _custom_emitter: FmodEventEmitter2D = $CustomEmitter
@onready var _bank_status: Label = %BankStatus
@onready var _contract_status: Label = %ContractStatus
@onready var _action_status: Label = %ActionStatus
@onready var _collect_button: Button = %CollectButton
@onready var _suction_start_button: Button = %SuctionStartButton
@onready var _suction_stop_button: Button = %SuctionStopButton
@onready var _progress_slider: HSlider = %ProgressSlider
@onready var _progress_value: Label = %ProgressValue
@onready var _custom_path: LineEdit = %CustomPath
@onready var _custom_play_button: Button = %CustomPlayButton
@onready var _custom_stop_button: Button = %CustomStopButton


func _ready() -> void:
	get_window().title = "Planet · FMOD 音效试听"
	%LoadBanksButton.pressed.connect(load_banks)
	%OutputTestButton.pressed.connect(test_audio_output)
	_collect_button.pressed.connect(play_collect)
	_suction_start_button.pressed.connect(start_suction)
	_suction_stop_button.pressed.connect(stop_suction)
	_progress_slider.value_changed.connect(set_suction_progress)
	_custom_play_button.pressed.connect(_play_entered_event)
	_custom_stop_button.pressed.connect(stop_custom_event)
	_custom_path.text_submitted.connect(play_custom_event)
	_collect_emitter.start_failed.connect(_on_start_failed.bind("收集"))
	_suction_emitter.start_failed.connect(_on_start_failed.bind("吸取"))
	_custom_emitter.start_failed.connect(_on_start_failed.bind("自定义"))
	_suction_emitter.stopped.connect(_on_suction_stopped)
	load_banks()


func load_banks() -> bool:
	_stop_all_audio()
	_reset_emitters()
	_unload_banks()
	_banks_ready = false
	_collect_ready = false
	_suction_ready = false
	_progress_ready = false
	var missing: PackedStringArray = []
	var paths: Array[String] = []
	for bank_name: String in BANK_NAMES:
		var bank_path: String = BANK_ROOT.path_join(bank_name)
		paths.append(bank_path)
		if not FileAccess.file_exists(bank_path):
			missing.append(bank_name)
	if not missing.is_empty():
		_bank_status.text = "待交付音频包：缺少 %s\n目录：%s" % [", ".join(missing), BANK_ROOT]
		_contract_status.text = "事件尚未检查。请从 FMOD Studio 构建并复制音频包，再点击重新加载。"
		_action_status.text = "可先点击「测试音频输出」，检查 FMOD 是否能够发声。"
		_update_controls()
		return false
	_bank_loader = FmodBankLoader.new()
	_bank_loader.name = "LoadedBanks"
	_bank_loader.bank_paths = paths
	_bank_host.add_child(_bank_loader)
	FmodServer.update()
	var loaded_paths: PackedStringArray = []
	for bank: FmodBank in FmodServer.get_all_banks():
		if (
			bank.is_valid()
			and bank.get_loading_state() == FmodServer.FMOD_STUDIO_LOADING_STATE_LOADED
		):
			loaded_paths.append(bank.get_godot_res_path())
	for bank_path: String in paths:
		if not loaded_paths.has(bank_path):
			_bank_status.text = "音频包未能加载：%s\n请检查构建版本和 Godot 输出。" % bank_path.get_file()
			_contract_status.text = "事件尚未检查。"
			_action_status.text = "修正音频包后重新加载。"
			_unload_banks()
			_update_controls()
			return false
	_banks_ready = true
	_bank_status.text = "已加载 3 个音频包：Master.strings.bank → Master.bank → SFX.bank"
	_check_contract()
	_action_status.text = "请选择音效试听；是否正常发声需要耳听确认。"
	_update_controls()
	return true


func are_banks_ready() -> bool:
	return _banks_ready


func play_collect() -> bool:
	if not _collect_ready:
		_action_status.text = "收集音未就绪：请检查音频包与 event:/Slime/Collect。"
		return false
	# Use the emitter's managed instance so reloading can stop this short event too.
	_collect_emitter.play()
	_action_status.text = "已请求播放收集音。请确认声音完整、没有意外循环。"
	return true


func start_suction() -> bool:
	if not _suction_ready or not _progress_ready:
		_action_status.text = "吸取音未就绪：需要循环事件和本地连续 Progress 参数（0～1）。"
		return false
	_suction_emitter.set_parameter("Progress", float(_progress_slider.value))
	_suction_emitter.play(false)
	_suction_active = true
	_action_status.text = "已请求开始吸取。拖动 Progress，听声音是否随进度变化。"
	_update_controls()
	return true


func stop_suction() -> void:
	_suction_emitter.stop()
	_suction_active = false
	_action_status.text = "已请求停止吸取；停止尾音由 FMOD 事件设置决定。"
	_update_controls()


func set_suction_progress(progress: float) -> bool:
	var value: float = clampf(progress, 0.0, 1.0)
	_progress_slider.set_value_no_signal(value)
	_progress_value.text = "%.2f" % value
	if not _progress_ready:
		return false
	_suction_emitter.set_parameter("Progress", value)
	return true


func play_custom_event(event_path: String) -> bool:
	var path: String = event_path.strip_edges()
	if not _banks_ready:
		_action_status.text = "请先加载音频包，再试听事件。"
		return false
	if not path.begins_with("event:/") or not FmodServer.check_event_path(path):
		_action_status.text = "找不到事件：%s。请核对路径并重新构建音频包。" % path
		return false
	var description: FmodEventDescription = FmodServer.get_event(path)
	if description.is_3d():
		_action_status.text = "该事件包含空间设置；此入口试听普通非空间事件，请移除空间设置后构建。"
		return false
	_custom_emitter.stop()
	_custom_emitter.event_name = path
	_custom_emitter.play()
	_action_status.text = "已请求播放：%s。可用「停止事件」结束循环。" % path
	return true


func stop_custom_event() -> void:
	_custom_emitter.stop()
	_action_status.text = "已请求停止自定义事件。"


func test_audio_output() -> bool:
	_stop_output_sound()
	if not FileAccess.file_exists(OUTPUT_TEST_FILE):
		_action_status.text = "输出测试缺少文件：%s" % OUTPUT_TEST_FILE
		return false
	if _output_file == null:
		_output_file = FmodServer.load_file_as_sound(OUTPUT_TEST_FILE)
	_output_sound = FmodServer.create_sound_instance(OUTPUT_TEST_FILE)
	if _output_sound == null or not _output_sound.is_valid():
		_action_status.text = "FMOD 输出测试无法开始，请检查 Godot 输出与音频设备。"
		return false
	_output_sound.play()
	_action_status.text = "已请求播放测试音。仅验证 FMOD 输出，不代表 Bank 事件通过；请耳听确认。"
	return true


func _check_contract() -> void:
	var messages: PackedStringArray = []
	if FmodServer.check_event_path(COLLECT_EVENT):
		var collect_description: FmodEventDescription = FmodServer.get_event(COLLECT_EVENT)
		_collect_ready = collect_description.is_one_shot() and not collect_description.is_3d()
		if _collect_ready:
			_collect_emitter.event_name = COLLECT_EVENT
			messages.append("收集：就绪（短音效）")
		else:
			messages.append("收集：请设为非空间短音效，不要添加循环")
	else:
		messages.append("收集：缺少 %s" % COLLECT_EVENT)
	if FmodServer.check_event_path(SUCTION_EVENT):
		var suction_description: FmodEventDescription = FmodServer.get_event(SUCTION_EVENT)
		_suction_ready = not suction_description.is_one_shot() and not suction_description.is_3d()
		if _suction_ready:
			_suction_emitter.event_name = SUCTION_EVENT
			messages.append("吸取：就绪（循环）")
		else:
			messages.append("吸取：请设为非空间循环音效")
		for parameter: FmodParameterDescription in suction_description.get_parameters():
			if parameter.get_name() == "Progress":
				_progress_ready = (
					not parameter.is_global()
					and not parameter.is_read_only()
					and not parameter.is_discrete()
					and not parameter.is_labeled()
					and is_equal_approx(parameter.get_minimum(), 0.0)
					and is_equal_approx(parameter.get_maximum(), 1.0)
				)
		messages.append("Progress：就绪（0～1）" if _progress_ready else "Progress：缺少本地连续参数（0～1）")
	else:
		messages.append("吸取：缺少 %s" % SUCTION_EVENT)
	_contract_status.text = "\n".join(messages)


func _update_controls() -> void:
	_collect_button.disabled = not _collect_ready
	_suction_start_button.disabled = not (_suction_ready and _progress_ready)
	_suction_stop_button.disabled = not _suction_active
	_progress_slider.editable = _suction_ready and _progress_ready
	_custom_play_button.disabled = not _banks_ready
	_custom_stop_button.disabled = not _banks_ready


func _play_entered_event() -> void:
	play_custom_event(_custom_path.text)


func _on_start_failed(event_label: String) -> void:
	_action_status.text = "%s事件无法开始，请检查 FMOD 构建和 Godot 输出。" % event_label


func _on_suction_stopped() -> void:
	_suction_active = false
	_update_controls()


func _stop_output_sound() -> void:
	if _output_sound != null and _output_sound.is_valid():
		_output_sound.release()
	_output_sound = null


func _stop_all_audio() -> void:
	for emitter: FmodEventEmitter2D in [_collect_emitter, _suction_emitter, _custom_emitter]:
		emitter.allow_fadeout = false
		emitter.stop()
	_suction_active = false
	_stop_output_sound()
	FmodServer.update()


func _reset_emitters() -> void:
	for emitter: FmodEventEmitter2D in [_collect_emitter, _suction_emitter, _custom_emitter]:
		emitter.event_name = ""
		emitter.allow_fadeout = true


func _unload_banks() -> void:
	if _bank_loader != null:
		_bank_loader.free()
		_bank_loader = null


func _exit_tree() -> void:
	_stop_all_audio()
	_reset_emitters()
	_unload_banks()
	if _output_file != null:
		FmodServer.unload_file(OUTPUT_TEST_FILE)
		_output_file = null
