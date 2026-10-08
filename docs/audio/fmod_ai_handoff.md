# FMOD 可行性验证与最新 Demo：Fred / AI 阅读入口

更新日期：2026-10-08。适用仓库：[planet](https://github.com/nOstalgia-April/planet/tree/audio/fmod-import)，分支：`audio/fmod-import`。

## 本次要完成什么

请协助 Fred 在自己的电脑上跑通 **FMOD Studio → Build Bank → Godot 独立试听**，反馈这条插件通路是否能用于后续音效制作。此次同步也包含最新游戏 Demo、玩法、美术资源和独立动画预览，可用于理解声音出现的情境。

截至本次更新，`assets/fmod/banks/` 只有占位文件，尚无制作好的 Bank。主游戏仍使用 Godot 原生 WAV；独立试听场景已经提供 FMOD 加载、播放、停止和参数控制。**插件初始化成功、Core WAV 能播放、Bank 事件通过、人工听感通过，是不同层次的结果，分别记录。**

本轮不要求 Fred 完成玩法代码或主游戏的 FMOD 迁移。音色、素材与最终声音方案由 Fred 判断；下面的事件名是现有验证场景的接口约定，不等于最终音频工程必须采用的完整设计。

## 取得完整更新

- 首次使用：在上述分支页面 **Code → Download ZIP**，完整解压后打开根目录 `project.godot`；也可使用下面的 Git 命令。
- 已使用 ZIP：下载新 ZIP 到新文件夹，再复制自己保存的 Bank。不要只下载一份手册或单个场景来覆盖旧工程。
- 已使用 Git：先检查状态。若有 Fred 自己的 Bank、源工程或其他未提交改动，先另存或提交；出现冲突时保留双方文件，不自动丢弃工作。工作区干净后再更新。

```sh
# 首次取得
git clone --branch audio/fmod-import https://github.com/nOstalgia-April/planet.git
cd planet

# 已有副本：先检查，保存本地工作后再运行后面的更新命令
git status --short
git fetch origin
git switch audio/fmod-import
git pull --ff-only origin audio/fmod-import

# 把实际分支与提交号记入反馈
git branch --show-current
git rev-parse --short HEAD
```

本机基准是 **Windows x64、Godot 4.7.2、FMOD GDExtension 6.1.0（发布包 6.1.0-4.5.0）、FMOD Studio 2.03.06**。插件和运行库已在仓库内，无需另装一套插件。其他系统是否可用应另行实测；带有对应平台库不等于已经完成该平台验证。

首次打开完整项目，等待资源导入完成，关闭再重新打开一次。若首次导入出现 `FmodServer` 接口错误，先完成这一步；重开仍报错再反馈完整错误，不擅自替换 DLL 或升级插件。

## 按用途选择入口

| 用途 | 入口 | 操作 / 范围 |
| --- | --- | --- |
| 验证 FMOD 插件与音频包 | `features/fmod_audio_test/fmod_audio_test.tscn` | 打开后 F6；本轮主要验收入口 |
| 体验最新游戏 Demo | `scenes/disk_demo.tscn` | F5；目前使用原生 WAV |
| 看物件动作和巢穴升级过程 | `features/物品动画预览/物品动画总览.tscn` | F6；可选物件、动作、循环与逐帧进度；[预览说明](../../features/物品动画预览/README.md) |
| 比较四种喷溅表现 | `features/splash_preview/splash_preview.tscn` | F6；说明见[喷溅预览手册](../../features/splash_preview/README.md) |

物品动画和喷溅是独立预览，不代表这些资源或对应音效已经接入主游戏。

### 给声音制作的 Demo 上下文

- 开局两座基础史莱姆巢穴；鼠标悬停怪物，吸管在中心逐只处理。`1` / `2` 切换工具，捕网解锁后左键投网。
- 解锁捕网会引入首座黏液怪巢穴。黏液怪站在黏液上时，先从黏液中拔出，再正常吸入；这两段需要能被玩家听出区别。拔出不等于收集成功，移开工具或切换视图会中断未完成处理。
- 吸管升级会让两个阶段都加快；试听时可关注持续声、阶段衔接和停止是否自然。具体声音设计不限定素材配方。
- 吸入成功产生收集反馈；解锁连击科技后连续吸入会产生连击奖励。捕网和自动采集是独立的收集来源。
- 向下滚一格进入星球总览，向上返回近景。近景在星球上按右键拖动，总览在空白背景按右键拖动；总览仅供观察，不能捕捉。
- 悬停巢穴查看治理操作，科技树和底部工具栏可查看解锁 / 升级。完整玩法说明在[项目 README](../../README.md)。

两阶段需求以 Notion 的[吸尘器任务](https://app.notion.com/p/3f0ab9cff760812fbad7cedb67273b90)为上下文。现有试听场景只有一个固定吸取事件和一个 `Progress` 滑条，**尚未模拟两阶段自动切换，也没有将滑条接入真实吸取过程**。不要把该场景误读成两阶段声音已经完成。

## 最短验证顺序

1. 用 F6 运行 FMOD 试听场景。没有 Bank 时，出现缺文件提示、事件按钮禁用是正常状态。
2. 点“测试音频输出”，请 Fred 确认是否听见声音。这使用 FMOD Core 播放已有 `assets/audio/collect.wav`，只检查基础输出。
3. 按[导入手册](fmod_import_guide.md)在 Studio 制作两个测试事件及参数，先在 Studio 确认声音能播放。素材可用项目现有声音或自己的可交付素材。
4. Build Desktop，把同次构建的三个 Bank 直接放到 `assets/fmod/banks/`，然后在试听场景点“加载 / 重新加载音频包”。
5. 测收集重复播放、吸取循环 / 停止 / 再次开始，以及 `Progress = 0 / 0.5 / 1` 和连续拖动。滑条值变化不等于声音变化，需要在 Studio 中设置自动化并人工试听。
6. 修改一次声音并重新 Build，停止事件后替换整套 Bank，重载后试听；关闭场景再 F6 复测。
7. 按[测试通路手册](fmod_test_route.md)的反馈模板提交结果。缺 Bank、缺设备或缺工具时填“未测 / 被阻塞”，不能当作已通过，也不能直接认定插件不可行。

## AI 可以直接核对的约定

| 项目 | 现有约定 |
| --- | --- |
| Bank 路径 | `res://assets/fmod/banks`，文件不能多套一层 `Desktop/` |
| Bank 文件 | `Master.strings.bank`、`Master.bank`、`SFX.bank`，同次 Desktop Build |
| 收集事件 | `event:/Slime/Collect`：非空间、一次播放、自然结束 |
| 吸取事件 | `event:/Tools/Suction`：非空间、持续循环、可停止 |
| 吸取参数 | `Progress`：事件内、可写、连续、范围 0–1；不是全局、离散或标签参数 |
| 自定义事件 | 也分配到 `SFX`，使用完整 `event:/...` 路径；现有入口拒绝 3D 事件 |
| 默认启动场景 | `scenes/disk_demo.tscn`；F5 不会进入 FMOD 试听 |

先读上述两份操作手册；需要排查实现时按以下顺序定位：

| 文件 | 读什么 |
| --- | --- |
| `project.godot` | `Fmod` 配置、`FmodManager` 自动加载与插件启用 |
| `addons/fmod/plugin.cfg`、`addons/fmod/fmod.gdextension` | 插件版本和当前平台库路径 |
| `features/fmod_audio_test/fmod_audio_test.tscn` | 按钮、状态标签、三个事件发射器 |
| `features/fmod_audio_test/fmod_audio_test.gd` | Bank 常量、`load_banks()`、`_check_contract()`、播放 / 停止与清理逻辑 |
| `scenes/disk_demo.tscn`、`scripts/disk_demo.gd` | 当前主玩法的原生音频节点及声音出现点 |
| `scripts/slime.gd`、`resources/prototype_settings.tres` | 如需理解实际脱附 / 吸入过程及可调时长，再读这些文件 |

优先核对文件、事件名、Bank 分配和 Studio 自动化。不要为了让测试变绿删除检查、绕过插件、修改玩法或把缺 Bank 状态伪造成成功。确需变更程序接口时，给常常提供错误、复现步骤和建议即可。

无界面启动只能确认部分程序通路，不能完成声音验收。若 AI 没有 Studio 或电脑操作能力，提供 Fred 可执行的操作步骤和待确认项，不编造 Build、点击、听感或播放结果。

## 什么结果足以继续推进

| 结果层次 | 所需证据 |
| --- | --- |
| 插件基础通路 | 在 Fred 的电脑成功打开试听场景，Core WAV 经人工确认可听见 |
| Bank / 事件通路 | 三个 Bank 成功加载；收集、循环、停止及参数变化均经人工试听确认；重载、重启后仍有效 |
| 声音设计反馈 | Fred 说明三档参数表达什么、循环和停止听感是否满意、还需调整什么 |
| 后续主游戏接入 | 上述结果和音频包交回后，再安排玩法触发接线；本轮不将它标为完成 |

交回同次 Build 的三个 Bank、可继续编辑的完整 Studio 源工程及依赖素材、素材来源说明，并附实际提交号、工具版本、操作结果和错误原文。源工程可另交压缩包，账号、安装包和无关素材不放入仓库。完整反馈模板在[测试通路末尾](fmod_test_route.md#10-给开发同事的反馈模板)。

## 2026-10-08 发布前核验记录

以本次待上传文件导出一个不含本机 `.godot` 缓存的完整副本，使用 Windows x64 / Godot 4.7.2 检查：

- 六项已有检查通过：`progressive_rules_check.gd`、`gameplay_revision_check.gd`、`demo_playthrough_check.gd`、`planet_view_controls_check.gd`、`ground_ecology_check.gd`、`物品动画检查.gd`。覆盖规则、零糖果自动通关、视图切换、黏液生态与独立物件动画。
- 主场景与 FMOD 试听场景的无界面启动完成，日志确认 FMOD 初始化成功；真实绘制的玩法检查也通过，并检查了 1280×800 近景和 1920×1080 总览截图。
- 全新导入时复现 `FmodServer` 临时接口报错；重新打开后接口报错消失。无界面编辑器退出时仍记录纹理 / 对象 / 资源未释放提示，尚未修复；它与 Bank 缺失是分别记录的问题，不能将本轮描述为全程无警告。
- 部分运行日志出现 Live Update 的 `9264` 端口占用警告。若 Fred 遇到同样情况，先保留日志、确认自己是否同时运行其他 FMOD 工程；本轮没有验证 Studio Live Update 连接。
- 本轮没有 Bank，未完成 Bank 事件、参数听感或真实耳听的 Core WAV 验收；也未验证导出成品与其他操作系统。这些仍待 Fred 的实际制作和试听结果。

本轮只同步已有实现并更新交接文档，没有改动插件版本或 FMOD 试听逻辑。

## 可直接发给 Fred 的 AI

```text
请先阅读当前 audio/fmod-import 分支的 docs/audio/fmod_ai_handoff.md，
再阅读 fmod_import_guide.md 和 fmod_test_route.md。
目标是协助我验证 FMOD Studio → Bank → Godot 独立试听的通路。
先核对分支、提交、工具版本和 Bank 文件，再带我逐步测试。
最新 Demo 和独立动画预览用于理解声音情境，主游戏尚未迁移到 FMOD。
保留我的本地工作，不自动更换插件或重构玩法。
请分别记录已验证、未测试、阻塞的问题和下一步；听感由我确认，
不要把无界面启动、接口成功或 Core WAV 输出写成 Bank 事件验收通过。
最后使用测试通路手册中的反馈模板汇总。
```
