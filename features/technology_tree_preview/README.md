# 科技树独立页面

在 Godot 打开 `technology_tree_preview.tscn` 按 F6。底部可切换开局、可购买、成长中和高阶四种状态；切换时重置预览进度。节点和右侧研究按钮使用真实购买规则。主游戏底部「科技树」打开同一页面，返回或 Esc 关闭。

## 图标与等级

每个升级项只显示一个图标，图标下方数字为当前等级；继续购买会更新该数字，不展开重复图标。吸取速率初始为 1 级；解锁捕网或连击后，其容量、奖励、间隔获得基础 1 级。尚未解锁的项目为 0 级。最高等级禁用购买。

- 已研究：保留分支色和勾选，仍可升级时按购买条件显示。
- 前置满足且糖果足够：金色亮边和轻微呼吸光。
- 糖果不足：保留分支色轮廓，详情显示差额。
- 前置未满足：灰色图标，仍能查看名称、费用、效果和条件。

## 当前九个科技项

吸取速率、巢穴培育、完全自动化在屏幕水平中央。高价值个体从巢穴培育横向分出。捕网解锁和连击解锁同为吸取速率 2 级（含初始等级）的分支；捕网解锁后研究扩容，连击解锁后分别研究奖励与间隔。

治理研究只有巢穴培育与完全自动化，费用为 20／100 糖果。现有逐巢建设阶段与 16／32／64 糖果费用保留；完全自动化研究开放后两个建设阶段。全场巢穴完成自动化时达成目标。

连击奖励保留 +1／+2／+3；间隔由基础 3 秒提升到 4／5／6 秒，试玩费用暂定 15／40／80 糖果，均在设置资源调整。间隔影响真实捕获续时与 HUD 倒计时。高价值个体研究只影响选中巢穴的未来刷新。

## 参考与采用范围

- [用户提供的分支示意](../../docs/references/technology-tree-layout-reference.png)：采用由下向上成长与分支连线。具体前置按用户本轮七点修正和“先解锁捕网，再研究扩容”的澄清。
- [用户提供的 Dirt Clicker 截图](../../docs/references/dirt-clicker-technology-reference.png)：采用深色背景、紧凑方形图标、细连线和可购买项的放射亮光。颜色状态映射按本项目要求实现，不推断截图的交互规则。

## 接入与所有权

- `scenes/ui/technology_page.tscn`：可复用页面；`refresh(run, nest_id)` 注入进度，`select_node(id)` 选择升级项。
- `scenes/ui/technology_node.tscn`：一个升级项及其当前等级。
- `PrototypeRun`：唯一拥有余额、进度及购买校验。前置由 `get_technology_prerequisites()` 提供给模型和页面。
- 全局购买 ID：`pipe`、`cultivation`、`automation`、`net_unlock`、`net_capacity`、`combo_unlock`、`combo_reward`、`combo_interval`；巢穴购买 ID 为 `valuable`。旧快捷入口 `net`、`governance`、`combo` 仍选择各自下一动作。
- 页面发出 `technology_upgrade_requested` / `nest_technology_upgrade_requested`，主 Demo 接入原有处理；`nest_selected` 同步目标，`close_requested` 返回。

价格和效果在 `resources/prototype_settings.tres`，节点位置在 `technology_page.gd` 的 `_node_position()`。右侧详情覆盖于完整画布之上，中央主线按屏幕中心定位。

## 验证

`tests/technology_page_check.gd` 检查九个图标、当前等级、同项连续购买、捕网和连击前置、奖励与间隔的独立实际效果、治理两步研究、满级拒购、巢穴目标、重开及主游戏接线。加 `-- --capture` 生成 1280×800 与 1920×1080 的状态截图，并检查居中、无重叠和详情不遮挡节点。

相关回归入口：`progressive_rules_check.gd`、`governance_demo_check.gd`、`overview_cluster_ui_check.gd`、`attraction_ui_check.gd`。历史 `collection_batch_check.gd` 仍假设开局捕网可用且只有三只初始实体，不作为当前规则的通过标准。

本机旧版 `gdformat` 不支持当前 Godot 的强类型循环与字典语法；格式整理在兼容副本完成后恢复全部显式类型，以 Godot 4.7.2 的解析和实机运行验证为准。已有 FMOD 实时更新端口占用警告不影响本次科技树检查。
