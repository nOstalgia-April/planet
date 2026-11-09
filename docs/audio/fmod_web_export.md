# FMOD 网页导出

网页版使用 FMOD HTML5 SDK 2.03.06 的 Studio JavaScript / WASM 运行库，直接加载当前 `bank/Desktop` 的三个 Bank。现有音乐淡入淡出、暂停、全局参数、循环音效和事件内命令继续由原来的游戏脚本与 FMOD Bank 驱动。

## 构建

在工程根目录运行 `tools/build_web.ps1`。首次构建通过 `-SdkZip` 指向 FMOD HTML5 SDK 压缩包；脚本只提取 Studio WASM 运行所需的 JS、WASM 与原始许可说明到 `web/fmod/`。默认输出为 `output/planet-web/`。

构建使用当前项目的 Godot 4.7.2 和匹配的 `web_nothreads_release.zip` 导出模板。`-GodotPath` 可指定引擎程序，`-OutputPath` 可指定交付目录。Windows 模板目录是 `%APPDATA%\Godot\export_templates\4.7.2.stable`。Linux 是 `$XDG_DATA_HOME/godot/export_templates/4.7.2.stable`（未设置时为 `~/.local/share/godot/export_templates/4.7.2.stable`），可直接运行 `python3 tools/build_web.py`。

`web/` 由 `.gdignore` 隔离，因为其中的 HTML5 适配器只应进入网页导出。构建时在 `artifacts/` 下创建独立暂存工程，素材使用硬链接，文本文件独立复制；不共享主工程导入缓存。PowerShell 入口在成功或失败后都会清理本次暂存工程及日志。

## 平台边界

- 桌面版仍使用原生 FMOD GDExtension，正式场景及游戏音频脚本不改写。
- 暂存工程去掉桌面编辑器插件，将 `FmodManager` 自动加载替换成网页 `FmodServer`。
- 构建将五种原生 FMOD 句柄类型替换为 `PlanetWebFmod` 的显式类型。遇到新的未适配原生类型会终止构建。
- 网页连接层来自 `web/godot/` 和 `web/planet_fmod.js`。HTML 加载完成 Bank 后启动 Godot，再通过真实点击启用浏览器音频。
- Bank 在网页运行库和 Godot 资源包中各保留一份，后者供现有文件存在性检查使用。
- 渲染采用 Compatibility；导出使用单线程，不依赖网页 GDExtension 或跨域隔离响应头。
- 导出集合从主场景、自动加载、主题开始，追踪资源、脚本类型及字符串形式的动态加载路径。它包含核心动画的全部分页贴图，避免只按场景显式依赖打包而漏图。
- 网页暂存工程只改复制出来的 `.import`：桌面 VRAM 贴图，以及开头动画和流星的无损全屏序列，改为 Lossy WebP（质量 0.85）。角色帧、界面和已经是 Lossy 的星球核心图集不动。仓库里的 `.import` 不改，桌面版仍用原来的 VRAM 或无损压缩。
- `近景星球` 的仓库导入写了 `size_limit=4096`。网页暂存把这个限制清掉，按 PNG 原尺寸打包，避免再缩小。桌面导入文件保持 4096。
- 不生成移动端 ETC2/ASTC。手机与触控适配属于另一项工作。
- `shaders/planet_art_blend.gdshader` 按源画布 8119×7866 和 5949×5701 对齐近景图层。这些边长超过 WebGL 规定的 4096 下限。按像素切块会拆开着色器里的单张采样器，所以保持原尺寸，需要桌面 GPU 的 `MAX_TEXTURE_SIZE` 至少为 8192。

## 启动与发布

输出目录的 `start-web.cmd` 调用 Python 本地服务器，打开 `http://127.0.0.1:8765/`。固定端口用于保持浏览器存档的来源地址。结束时关闭启动器窗口。

部署时上传完整目录，保持相对路径；`.wasm` 使用 `application/wasm`。建议网站启用 HTTP 压缩以缩短首次下载时间。不要直接用 `file://` 打开 HTML。

## 验证范围

最小验证使用真实 Bank，分别播放主菜单音乐及 `Vacuum_On`，测到浏览器音频节点的非零 PCM 波形；停止音乐及播放 `Vacuum_Off` 后波形归零。连接层验证包含事件枚举、全局与局部参数读取，以及实例状态与时间线查询。

完整游戏检查覆盖主菜单、开场、正式游玩、吸取与奖励、暂停和静音；同时检查浏览器脚本错误和 FMOD 返回错误。桌面回归使用 `tools/check_editor_startup.ps1` 的三轮图形编辑器启动、保存场景恢复与脚本文档缓存重建。验证截图与暂存文件用后清理。

2026-10-19 实测：Edge 中实际吸取触发了 Vacuum_On、Vacuum_Loading、SuckUp_Pop、Candy_Acquire 和 Vacuum_Off；静音时 PCM 归零，暂停时怪物实例暂停、音乐实例继续。最终包重载后成功恢复了 7 糖果的浏览器存档，未发现脚本或 FMOD 错误。桌面图形编辑器三轮检查全部通过。最终目录 501,465,278 字节，ZIP 183,761,600 字节，ZIP 完整性检查通过。

## 本次临时文件收尾限制

2026-10-19，验证浏览器、本地服务器和 Godot 检查进程均已结束。执行工具拒绝了本任务临时文件的删除操作，返回 `blocked by policy`，具体规则未知；未改用其他语言或工具绕过拦截。以下文件尚未清理，不是批准长期保留的资料，也不应作为后续画面依据：

- `artifacts/web_fmod_01a153d5/`：约 1115.8 MiB 的文件，其中约 338.9 MiB 为指向正式素材的硬链接，其余主要为独立导入缓存与验证输出。
- `artifacts/editor_startup_20261019_191303_561/`：约 0.9 MiB，首次超时检查。
- `artifacts/editor_startup_20261019_191604_132/`：约 2.7 MiB，三轮通过检查。
- `tools/__pycache__/build_web.cpython-311.pyc`：18,714 字节；同目录其他文件属于之前的任务。
- `scripts/platform/`：本任务留下的空目录；网页适配器正式源码已经归入 `web/godot/`。

正式交付位于 `output/planet-web/` 和 `output/planet-web-fmod-20261019.zip`，不属于上述清理范围。
