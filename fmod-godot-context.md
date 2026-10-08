# 项目背景：吸尘器 / 粘液游戏（FMOD + Godot）

> 这份文件整理自 claude.ai 上的一段对话，供 Claude Code 了解项目现状。
> "已完成"表示用户实际测试过；"建议/待做"表示讨论过但未确认是否实施。

## 技术栈
- 音频中间件：FMOD Studio 2.03（项目文件 `ProjectVacuum_FMOD.fspro`）
- 游戏引擎：Godot（版本待确认，按 Godot 4 讨论）
- 游戏内容：用吸尘器吸粉色粘液怪，物体会卡在粘液里需要拔出

## FMOD 事件结构（当前）

| 事件 | 作用 | Bank |
|---|---|---|
| `Vacuum_Loop` | 吸尘器持续吸气声，主体音效 | `#referenced`（不单独分配，由其他事件引用） |
| `Vacuum_On` | 开机，启动 Vacuum_Loop（推测通过 Command Instrument 的 Start Event） | 未分配 |
| `Vacuum_Off` | 关机，Command Instrument → Stop Event → Vacuum_Loop | 未分配 |
| `Slime_Enter` | 进入粘液，Command Instrument → Set Parameter InSlime | 未分配 |
| `Slime_Exit` | 离开粘液，Pop 短音效 + Command Instrument → Set Parameter InSlime | 未分配 |

**已确认的行为：**
- Vacuum_Off 的 Stop 命令可以直接停掉 Vacuum_Loop（用户实测）。
- 停止 Vacuum_On 不会影响 Vacuum_Loop（它只负责发出启动命令）。

### Vacuum_Loop 内部
- **循环**：Loop Region + 两条轨道交替淡入淡出，实现循环点的周期性 crossfade。
  公式：Audio 1 右边缘 = B + 淡化长度并在 B 处淡出；Audio 2 为副本，从音频 A 点开始、放在时间线 B 位置并淡入；Loop Region = B 到 2B − A。
- **关机降调**：Master 的 Macros 上 Pitch 和 Volume 各加一个 AHDSR，靠 Release 实现停止时降调淡出（ALLOWFADEOUT 停止时才生效）。
  - AHDSR 的 **Clock Source 已改为 Instance**（Global 时在 Sandbox 中降调会瞬间完成；改为 Instance 后正常）。
- **粘液低通**：Master 上 Lowpass Simple，Cutoff 由参数 `InSlime` 自动化（粘液外约 22000 Hz，粘液里约 800 Hz）。

## 参数

| 参数 | 类型 | 范围 | 状态 |
|---|---|---|---|
| `InSlime` | 已改为 Global；当前为 Continuous 0–1 | 0 = 粘液外，1 = 粘液里 | 已实现 |
| `VacuumOn` | Global，Labeled（Off/On） | 开机状态标记 | 建议/待做 |

**平滑过渡**：FMOD 2.03 中 Seek Speed 改为 Seek 调制器。0.2 秒过渡 = 速度 5/秒（范围 0–1 时）。

## 待解决：防止误触 Slime_Exit 播放 Pop（建议方案，未确认实施）
1. `InSlime` 改为 Labeled（Out / In），兼作状态记录；平滑过渡改为在 Lowpass Cutoff 上加 Seek 调制器。
2. Slime_Exit 的 Pop 音频加触发条件：`InSlime = In` 且 `VacuumOn = On`。
3. Slime_Exit 的 Set Parameter 命令往后挪约 50 ms，确保 Pop 先检查状态、命令后改状态。
4. Slime_Enter 同理：有声乐器加条件 `InSlime = Out`，命令延后设为 In。
5. Vacuum_On 在 0:00 加命令 `VacuumOn → On`；Vacuum_Off 加命令 `VacuumOn → Off`（视游戏逻辑可同时重置 `InSlime → Out`）。
6. 注意：这套保护要求关机必须通过 Vacuum_Off 事件，否则 VacuumOn 不会重置。

**分工原则**：粘液状态本质是游戏状态，主要由 Godot 代码保证只在状态真正变化时播放事件；FMOD 的条件作为保护层。

## 测试方式
- FMOD Sandbox（Window → Sandbox）：按顺序播放 Vacuum_On → Slime_Enter → Slime_Exit → Vacuum_Off。
- 注意：Command Instrument 的 Stop 命令不会停止由事件乐器（嵌套）创建的实例。

## 发布前待办
- [ ] 把 Vacuum_On / Vacuum_Off / Slime_Enter / Slime_Exit 分配到 Bank（目前都是 #unassigned）
- [ ] 在 Godot 中接入 FMOD（游戏端只需播放这四个事件）

## Godot 当前问题：中文显示为方框
原因：默认字体没有中文字形（数字和英文显示正常）。
建议方案：
1. 导入 Noto Sans SC（思源黑体，开源可商用）到 `res://fonts/`
2. Project Settings → GUI → Theme → Custom Font 设为该字体（需开启 Advanced Settings）
3. 若部分节点仍是方框：检查 Theme Overrides → Fonts 或自定义 Theme 的 Default Font
4. 若想保留原英文字体：在原字体的 Import 面板 → Fallbacks 加入中文字体并 Reimport
5. 网页导出时注意中文字体体积较大，可考虑字体子集化
