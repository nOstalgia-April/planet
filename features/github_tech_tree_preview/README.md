# godot-tech-tree 应用预览

打开 `github_tech_tree_preview.tscn`，按 F6。独立预览使用当前 Demo 的十一项科技、图标、详情面板与真实购买模型；状态按钮复用原科技预览的开局／可购买／成长中／高阶四组进度。

左键点击查看，拖动节点重新排布，右键拖动画布，滚轮或底部滑条缩放（65%–160%）。「恢复布局」只重置位置与缩放，保留购买进度。Esc 返回主菜单。

## 参考与采用

- 来源：[jcreager/godot-tech-tree](https://github.com/jcreager/godot-tech-tree) 与[作者说明及实际截图](https://joecreager.com/godot-tech-tree/)。原图存于 `artifacts/godot_tech_tree_source.png`。
- 原图观察：上方起点、下方分支、方形节点、直线连接、左上缩放和右上 Reset。作者代码提供节点拖动与连线随动。
- 本预览按用户要求采用自下向上的分支排布，三个起点位于底部，解锁项与高阶升级向上展开；保留节点拖动、连线随动、缩放和布局复位，以及本项目的深色背景、彩色图标、等级、可购状态与右侧详情。实际前置只有模型定义的八条线：基础价值、吸取速率、巢穴培育为三个独立起点，避免把开局可购科技画成有前置门槛。
- 原仓库使用 Godot 3 的场景格式与 API。本预览在 Godot 4 上实现相应交互，未复制原仓库脚本或 Godot logo。原仓库的 Reset 会清空节点解锁状态；这里按当前 Demo 的需求只恢复布局。

## 范围

正式游戏底部「科技树」已使用 `scenes/ui/interactive_technology_page.tscn`，行为位于 `scripts/ui/interactive_technology_page.gd`。本目录的页面为兼容入口，独立预览和科技调参工具复用同一正式页面；缩放、恢复布局及操作提示直接放在页面内。

正式页面继承现有 `technology_page.gd` 的购买、状态和详情逻辑。`PrototypeRun` 继续唯一持有游戏进度；页面只持有位置、缩放和拖动状态。关闭清理未结束的拖动，重开页面保留当前排布；「恢复布局」不重置研究。打开页面暂停游戏，返回与 Esc 恢复游玩。

## 验证

`capture_preview.gd` 用实际鼠标事件验证购买、前置拦截、一次性全局研究、拖动、滚轮缩放、右键移动与布局复位后保留进度。检查两种尺寸的节点边界、无重叠与按钮可见，并保存 `artifacts/github_tech_tree_available_1280x800.png`、`artifacts/github_tech_tree_available_1920x1080.png` 和高阶已研究截图。

本机 Godot 4.7.2 实机检查通过。旧版 `gdformat` 不识别带类型的循环，按项目既有方法在兼容副本格式化后恢复类型；最终以引擎解析为准。

正式接入检查使用 `tests/game_technology_check.tscn`：从游戏按钮进入，验证暂停时的拖动与缩放、缩放 HUD 下的鼠标跟随、恢复布局、真实购买、前置拦截、全局研究、返回／Esc、新游戏复位和两种尺寸截图。位置计算使用完整画布变换，兼容游戏 HUD 与调参工具的父节点缩放。
