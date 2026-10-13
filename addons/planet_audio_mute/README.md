# Godot 运行窗口静音同步

这个编辑器插件把运行窗口的静音状态同步给 `GameAudio`，覆盖绕过 Godot AudioServer 的 FMOD 输出。Godot 原有调试消息、暂停和远程检查保持正常。

- 编辑器的原生 Game view 按钮拥有编辑器静音状态；插件仅按该按钮的编辑器图标读取状态，并用 `EditorDebuggerSession.send_message()` 发出 `planet_audio:set_editor_muted`。
- `GameAudio` 接收状态，统一控制 FMOD `bus:/` 和原生 Master。运行初始读取 `--debug-mute-audio`，注册消息后发送 `planet_audio:ready` 取得当前状态，避免调试会话启动早于自动加载节点。
- 玩家设置由 `GamePreferences.audio_enabled` 保存，编辑器状态不保存。两种静音状态按“任一个关闭就静音”组合；音量调整、音乐交叉淡入淡出和场景切换不能覆盖编辑器静音。
- 加载插件需要重开已打开的项目。插件对运行中的所有调试会话同步，包括独立运行窗口和编辑器内嵌窗口。

Godot 4.7.2 实际编辑器检查通过：

```text
godot --headless --path . --editor --script tests/editor_audio_mute_check.gd
```

检查在本次启动的编辑器中操作原生静音按钮并启动两个测试游戏进程，验证实际调试通信、FMOD 和原生总线、游戏静音隔离及重新运行；不改写玩家偏好。运行时伴随场景需要从这个编辑器检查启动。

本机旧版 `gdformat` 不支持显式类型循环及既有的 `not in` 写法。本次八份相关脚本通过临时兼容副本格式检查，正式文件保留类型，并以 Godot 4.7.2 的解析和运行检查为准。

当前 Godot 没有公开运行窗口静音信号或可供脚本调用的 debug-mute getter，因此按钮匹配限定在 `GameView` 下，以 `AudioMute`／`AudioStreamPlayer` 图标识别，不依赖翻译后的提示或自动节点名称。引擎升级需重新运行上述检查。实现依据：[Godot 原生按钮和静音消息](https://github.com/godotengine/godot/blob/master/editor/run/game_view_plugin.cpp)、[AudioServer 内部调试静音](https://github.com/godotengine/godot/blob/master/servers/audio/audio_server.cpp)。
