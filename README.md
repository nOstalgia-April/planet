# 圆盘玩法 Demo

本窗口的探索范围是 2D 连续圆盘上的收集与经营体验。入口为 `scenes/disk_demo.tscn`，在 Godot 中打开后按 F6，也可运行当前主场景。

## 音效协作

FMOD 导入与试听工具位于 `audio/fmod-import` 分支。

- [FMOD 导入手册](docs/audio/fmod_import_guide.md)：准备事件、构建音频包并导入项目。
- [FMOD 测试通路手册](docs/audio/fmod_test_route.md)：独立试听、参数检查和问题反馈。
- 试听入口：在 Godot 打开 `features/fmod_audio_test/fmod_audio_test.tscn`，按 F6。

当前主玩法仍使用原有四个 WAV 音效。这个分支提供 FMOD 插件与独立试听通路，实际音频包由音效同事在 FMOD Studio 中制作。

## 主玩法

管子吸口对准鼠标自由移动。按住左键时，只处理距离吸口最近且在处理范围内的一只史莱姆；附近最多四只额外史莱姆有轻微偏移、倾斜和拉长的吸力表现，不会增加处理进度。切换最近目标会清除旧目标进度，管子始终是单体连续工具。每只处理完成后立即消失并腾出存量，右侧显示本趟累计糖果；松手时一次加入余额，可在任何位置结算。

按 `1` 切换管子，按 `2` 切换捕网，也可点击右侧工具按钮。捕网点击一次后自动完成投网、收网和付款；收网结束时，按距离网心从近到远选取范围内的史莱姆，最多达到当前容量，每只获得 2 糖果。它按数量一次结算，不使用管子的处理速度，也不进入管子的待结金额。冷却从成功施放起计时，初值 6 秒；按住不会连续施放，空网也占用冷却。切换工具会结清管子当前批次，但不取消已投出的网或重置冷却，可切回管子继续处理。

点击巢穴查看驯化投入，右侧分别升级当前工具和巢穴。开局三个活跃巢穴，累计生成五个。每个巢穴三次投入后停止刷怪、缩成花束并自动产糖，同时释放活跃名额。剩余小怪失去巢穴后可在整圈可通行地表游走。五个目标全部完成后恢复绿色并结束本轮。

两条科技独立：管子只升级速度，每只处理时间为 0.6、0.45、0.32、0.22 秒，处理半径固定 24、视觉吸力半径固定 70；捕网只升级容量，每网最多 10、20、30、40 只，网幅半径固定 84，冷却固定 6 秒。两条科技各自的三档价格都是 10、30、70 糖果。管子同一趟的累计收集数量没有上限，但始终逐只处理。巢穴驯化价格为 20、60、180 糖果，刷怪间隔为 0.5、0.3、0.18 秒。本轮 Demo 的试玩数值不改动 Notion 正式策划。

未驯化巢穴按等级限制当前地表存量：一级 10 只、二级 40 只、三级 100 只。吸入时立即腾出名额，巢穴可以继续补刷，待结糖果不占存量。升级后允许补到新上限，驯化后停止刷新；已有小怪保留原巢穴编号并可继续收集。巢穴详情显示当前存量和上限。

默认设计视口为 1920×1080，窗口参数同步为该尺寸。界面和星球按当前视口缩放，宽屏额外空间分给玩法区；商店靠右，重启和操作提示靠底。输入使用实际控件区域。

活跃巢穴周围的小怪活动范围已扩大。小怪脚底朝球心，随所在位置径向旋转，沿环形地表站立。出巢时有短促弹跳，连续刷新方向按错开的序列加少量扰动分散；失巢后解除局部限制，但不走进圆盘中央装饰海域。

## 可调入口

本轮从 `scenes/disk_demo.tscn` 根节点的检查器调整：

- `capture_surface_inner_offset`：可吸地表向圆盘内延伸的距离，初值 65。
- `capture_surface_outer_offset`：可吸地表向圆盘外延伸的距离，初值 35。鼠标的可吸范围在这段地表区域外再按当前工具半径扩展；实际吸取仍要求鼠标与小怪躯干之间的距离不超过工具半径。
- `attraction_visual_limit`：管子周围有吸力表现的额外史莱姆数量，初值 4；表现偏移不影响真实命中点或结算。
- `resources/prototype_settings.tres`：分别配置管子处理时间、管子固定范围、捕网容量、网幅、冷却和各自科技价格；`nest_population_limits` 保留 10、40、100。
- `scenes/world/pipe_cursor.tscn`：独立管子场景，可调管长、弯曲、吸口及外围吸力表现，无机身。
- `scenes/world/capture_net.tscn`：可独立预览的捕网表现，`cast_seconds` 初值 0.18、`close_seconds` 初值 0.35；成功收网在原位置播放数量和展开亮圈，冷却显示灰圈及倒数。捕获与奖励由主控和规则状态处理。

规则状态由 `PrototypeRun` 统一结算，`NestState` 保存每个巢穴的状态；场景脚本负责输入、显示和反馈。管子用 `collect_slime()` 累计待结金额、`settle_collection()` 一次入账；捕网用 `begin_net_cast()` 开始冷却、`collect_net_batch()` 扣除有效存量并直接付款。`pipe_level` 和 `net_level` 独立保存。重新开始会清空待结金额、施法阶段和冷却，最终目标完成时先结清已有管子成果。使用五个沿圆周分布的预设位置，按合法的活跃名额补巢。

数值是试玩初值，尚未形成平衡结论。本轮使用占位美术，未加入开发控制台。

## 检查

使用 Godot 4.7.2：

```text
godot --headless --path . --script tests/prototype_rules_check.gd
godot --headless --path . --script tests/disk_demo_check.gd
godot --headless --path . --script tests/capture_target_limits_check.gd
godot --headless --path . --script tests/collection_batch_check.gd
godot --headless --path . --script tests/layout_check.gd
godot --headless --path . --script tests/slime_roaming_check.gd
godot --headless --path . --script tests/demo_playthrough_check.gd
godot --path . --script tests/disk_demo_check.gd -- --capture
```

规则检查覆盖两路独立升级、管子待结与捕网即时付款、网容量、冷却及三级巢穴存量。单体检查覆盖最近目标、重叠仍只处理一只、视觉吸力不改变命中点或进度、目标切换及各档串行耗时。集成检查覆盖管子连续处理与松手结算、捕网自动完成、容量截断、冷却和切换工具，以及两路收入共存。布局检查覆盖 1920×1080 和 1280×800；实机场景检查验证巢穴点击并保存管子吸力、网爆发、冷却和完成画面到 `artifacts/`。从零资源的模拟只验证经济路径可达，真人操作感与两种科技的平衡仍由实际试玩判断。

本机旧版 `gdformat` 无法解析 Godot 4.7 的显式类型循环；相关脚本对规范化副本进行格式检查并保留源文件类型，以目标引擎解析与运行结果为准。

## 来源

- [基础策划 v0.2](https://app.notion.com/p/3ecab9cff76081c2a0e9f837df169e17)
- [开发规格：原型建议、暂定参数与验证](https://app.notion.com/p/3ecab9cff7608129b63dede19ed86c90)
- [A Planet of Mine 开发者截图](https://www.tuesdayquest.com/games/aplanetofmine/)：借鉴圆形主体、边缘资源与选中对象详情的层级；本作沿用连续地表和两种糖果投资。
