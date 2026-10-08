# FMOD 音效导入手册

2026-10-08 更新：首次接手或使用 AI 协助时，先看 [FMOD / 最新 Demo 交接入口](fmod_ai_handoff.md)。本页负责 Studio 制作与 Bank 导入，实际测试步骤见 [测试通路](fmod_test_route.md)。

这份手册用于把音效制作成 FMOD Bank，放进 `audio/fmod-import` 分支，并在独立试听场景中检查。当前主游戏仍使用 Godot 原生音效；本分支提供导入和试听通路，不代表最终音效已经接入玩法。仓库初始不含可试听的 Bank，需要音效同事先制作并 Build；也可以先用场景中的“测试音频输出”按钮，直接试听项目已有 WAV，确认 FMOD 输出设备通路。

## 1. 取得正确分支

不熟悉 Git 时，可以直接在浏览器打开 [audio/fmod-import 分支](https://github.com/nOstalgia-April/planet/tree/audio/fmod-import)，确认分支选择器显示 **audio/fmod-import**，点击 **Code → Download ZIP**，然后完整解压。不要在 `main` 分支下载；每次更新需要重新下载该分支的 ZIP。

使用 Git 时，第一次取得项目：

```sh
git clone -b audio/fmod-import https://github.com/nOstalgia-April/planet.git
cd planet
```

已经有项目副本时，先运行 `git status --short`，将自己的 Bank、源工程和其他改动另存或提交。工作区干净后再执行；出现冲突时保留本地工作，不使用强制覆盖：

```sh
git fetch origin
git checkout audio/fmod-import
git pull --ff-only origin audio/fmod-import
```

使用 Godot **4.7.2** 打开项目根目录中的 `project.godot`。仓库已经带有并启用了 **FMOD GDExtension 6.1.0-4.5.0**，无需重复下载或安装插件。该扩展发布包面向 Godot 4.5，并使用 FMOD 2.03.06；本项目在 Godot 4.7.2 上已检查扩展导入与运行时 API。真实音效的播放、参数变化与听感仍需用制作后的 Bank 验证。[扩展发布说明](https://github.com/utopia-rise/fmod-gdextension/releases/tag/6.1.0-4.5.0)

**首次打开完整项目时，等资源导入完成，再关闭并重新打开项目一次，然后开始试听。** 全新副本检查中，首次导入会出现 `FmodServer` 的临时接口报错，重新打开后恢复正常。没有制作 Bank 时，编辑器提示找不到 `Master.strings.bank` 是预期状态。重开后仍报错时，把完整错误文本交给开发同事。

## 2. 安装制作工具

在 [FMOD 官方下载页](https://www.fmod.com/download) 登录 FMOD 账号，下载并安装 **FMOD Studio 2.03.06**，让制作工具与仓库里的运行库版本一致。Godot 负责运行和试听，FMOD Studio 负责编辑事件、参数和生成 Bank。

新建 Studio 工程，保存为例如 `PlanetAudio.fspro`。源工程应放在自己的音频工作目录中，不要把 `.fspro` 或原始素材直接放进 `assets/fmod/banks/`；这个项目目录只用于放 Build 后的运行包。

## 3. 遵守名称与目录约定

以下名称区分大小写，填写时保留 `/`、前缀和拼写，不添加空格。

| 项目 | 必须使用的值 | 用途 |
|---|---|---|
| Godot Bank 目录 | `res://assets/fmod/banks` | 也就是项目中的 `assets/fmod/banks/` |
| 字符串 Bank | `Master.strings.bank` | 按事件路径查找事件 |
| 主 Bank | `Master.bank` | Studio 主混音信息 |
| 音效 Bank | `SFX.bank` | 当前两个测试事件及其媒体 |
| 收集事件 | `event:/Slime/Collect` | 一次播放后自然结束 |
| 吸取事件 | `event:/Tools/Suction` | 开始后循环，点击停止后退出 |
| 吸取参数 | `Progress` | 事件内连续参数，范围 `0.0` 到 `1.0` |

Studio 中的事件文件夹是 `Slime` 和 `Tools`，事件名称是 `Collect` 和 `Suction`；`event:/` 是在 Godot 中引用时使用的前缀。

项目设置已经配置如下，无需重新调整：

| FMOD 设置 | 当前值 |
|---|---|
| Auto Initialize | 开启 |
| Should Load By Name | 开启 |
| Banks Path | `res://assets/fmod/banks` |

初始化和 Bank 加载背景可查阅维护者的[初始化说明](https://fmod-gdextension.readthedocs.io/en/latest/user-guide/2-initialization/)与[加载说明](https://fmod-gdextension.readthedocs.io/en/latest/user-guide/4-loading-banks/)。本分支的试听场景提供加载按钮，不需要音效同事编写调用代码。

## 4. 先做一个可确认的收集事件

1. 在 Studio 新建一个非空间的 **2D Timeline 事件**，放进 `Slime` 文件夹，命名 `Collect`。
2. 导入仓库现有的 `assets/audio/collect.wav`，把它放到该事件的音频轨道上。
3. 保留一次播放的行为，不加循环区域；在 Studio 按播放，确认能听见完整的一声。
4. 在 Banks 面板建立名为 `SFX` 的 Bank。
5. 对收集事件执行 **Assign to Bank → SFX**。

这个旧音效只用于确认整条导入通路。通路通过后，可以用自己制作的收集声音替换媒体；只要事件路径保持不变，Godot 的固定收集按钮就不需要改代码。[Studio 官方入门教程](https://www.fmod.com/docs/2.03/studio/quick-start-tutorial.html)

## 5. 做吸取循环与 Progress 参数

1. 新建非空间的 2D Timeline 事件，放进 `Tools` 文件夹，命名 `Suction`，并 **Assign to Bank → SFX**。
2. 放入自己制作或明确获得授权的吸力声音，用时间线循环区域让事件持续播放。先在 Studio 确认循环衔接和停止行为。
3. 为这个事件添加名为 `Progress` 的**连续、事件内参数**，最小值 `0`、最大值 `1`，默认值建议 `0`。不要做成全局参数、离散参数或标签参数。
4. 给参数添加实际声音变化，例如音调、滤波或不同强度素材的混合。仅创建参数而不设置自动化，滑条不会改变听感。
5. 在 Studio 检查 `0`、`0.5`、`1` 三个值：推荐分别表现吸取开始、中段、接近完成，并保持整体音量可控。

`Progress` 描述吸取进度，不负责让事件自行结束。独立试听场景由“开始吸取 / 停止吸取”按钮控制循环是否播放。首次验证使用 2D 事件，先排除监听器位置和距离衰减的干扰。[Studio 参数说明](https://www.fmod.com/docs/2.03/studio/parameters.html)

## 6. Build 并复制 Desktop 音频包

1. 保存 Studio 工程，确认两个事件都已分配到 `SFX`。
2. 使用 **File → Build**，生成 **Desktop** 平台的 Bank。到 Studio 工程配置的输出目录寻找结果，常见位置是 `Build/Desktop/`。
3. 检查同一次 Build 的结果中包含下面三个文件，再把它们一起复制到项目的 `assets/fmod/banks/`。不要把文件多放进一层 `Desktop/` 子目录。

```text
planet/
└─ assets/
   └─ fmod/
      └─ banks/
         ├─ Master.strings.bank
         ├─ Master.bank
         └─ SFX.bank
```

4. 打开 Godot 场景 `res://features/fmod_audio_test/fmod_audio_test.tscn`，按 **F6** 运行当前场景。
5. 场景启动时会自动尝试加载一次。点击“加载 / 重新加载音频包”，再测试“播放收集音”和“开始吸取”；详细步骤见 [FMOD 测试通路](fmod_test_route.md)。

没有 Bank 时，状态区会显示缺少的文件名，事件按钮不可用；“测试音频输出”仍可用，它通过 FMOD Core 播放仓库自己的 `assets/audio/collect.wav`。这个结果只验证 FMOD 能输出声音，不能证明 Bank、事件路径或 `Progress` 参数已经通过。

三个 Bank 应始终来自同一次 Build。更新时先在试听场景停止所有事件，再复制新文件并点击重新加载。若状态或试听仍显示旧结果，停止场景并重新按 F6；重启后应仍能加载同一套文件。

新增自己的测试音效时，创建非空间的 **2D Timeline 事件**，例如 `event:/Tests/MySound`，同样分配到 `SFX` 并重新 Build。试听场景的任意事件路径输入区可验证播放和停止；此入口不支持含空间设置的 3D 事件。不要为了测试新声音改掉两个固定事件的名字。

## 7. 交付给项目同伴

请交付两部分，并注明 Studio 版本、Build 平台与制作日期：

- **可运行音频包**：同一次 Desktop Build 的 `Master.strings.bank`、`Master.bank`、`SFX.bank`，放在约定的 Bank 目录中。可通过本分支提交这些文件。
- **可继续编辑的源工程**：完整 `.fspro` 所在工程及其依赖文件、原始/处理后素材、素材来源与授权说明。可以作为单独的交付压缩包；仅交付 `.fspro` 一个文件不能保证同伴能够继续编辑。不要夹带 Studio 安装程序、SDK、账号信息或无关示例媒体。

同时附上两个事件的试听结果、`Progress` 三档设计含义，以及是否需要下一步接入主玩法。独立场景通过后，主游戏接入仍是后续工作。

## 8. 素材与许可范围

插件代码的 MIT 许可与 FMOD 原生库的许可分别适用。本仓库文档不把主项目全部源码和美术授予 MIT 许可；其他源码、素材按各自的授权范围处理。FMOD SDK 的开发工具和非运行时文件不随音效交付分发；本分支保留的运行库仍受 FMOD 自身条款约束。[FMOD 许可](https://www.fmod.com/legal)

测试与交付使用自己的声音、项目现有声音或明确可分发的素材。不要把 FMOD 自带 Demo 工程的媒体、示例音乐或其他未获分发授权的素材提交到公开仓库。发布游戏时还需按项目适用许可处理署名。[FMOD 署名要求](https://www.fmod.com/attribution)
