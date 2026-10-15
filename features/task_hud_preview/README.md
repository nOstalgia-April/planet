# 任务 HUD 布局预览

在 Godot 打开 `task_hud_preview.tscn`，按 F6 运行。

- 使用当前近景游玩场景作为背景，任务牌位于金币栏下方。
- 这是独立预览，正式入口和正式 HUD 没有引用任务牌。
- 示例为已解锁巢穴培育、持有 2,850 糖果，目标为「完全治理」。4,500 费用读取当前配置。
- 面板文案、科技图标和进度条是 `task_hud.tscn` 中的可编辑节点；底板由 Edge 网页版 ChatGPT 生成。
- 根节点的 `preview_candy` 可调整预览初始数值。任务提示是布局示例，没有实现自动推荐、任务完成或跳转系统。
- 原有连击条在本预览中下移至 y=232；任务牌逻辑坐标为 (28, 76)，大小为 324×144，沿用当前 HUD 的缩放。
- 原始 PNG 保留在 `assets/ui/task_hud_preview/task_panel_web_v1.png`，AtlasTexture 只截取透明边距，原图未改写。

设计依据：本次运行的近景背景、科技弹窗 `assets/ui/technology/tooltip.png` 与底部工具区。沿用暗色喷刷颗粒、粉色手绘边缘、白色图标；层级依次为「优先解锁」、科技名、效果、费用进度。常驻任务的边框亮度低于可购买按钮。

查阅了《漂泊牧歌》官方 Steam 展示，但所查看的截图隐藏了 HUD，未将其作为任务栏布局证据。当前方案以本项目实际画面为准。来源：https://store.steampowered.com/app/1121640/The_Wandering_Village/

截图命令参数：运行本场景并传入 `-- --capture-task-hud`，生成本次 1920×1080 与 1280×800 截图到 `artifacts/task_hud_20261015/`。
