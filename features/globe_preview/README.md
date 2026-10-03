# 地球仪预览

在 Godot 中打开 `res://features/globe_preview/globe_preview.tscn`，按 **F6** 运行当前场景。它不接入现有玩法，也不修改项目的默认启动场景。

本机独立 Windows x64 近景版位于 `output/globe_preview/PlanetGlobePreview-Windows-RegionZoom.zip`。导出的安装包不随源码仓库上传；从仓库运行本预览时，使用 Godot 打开上面的场景。独立版本解压后运行 `PlanetGlobePreview.exe`，程序内置场景和怪物图片，使用 Compatibility 渲染。

独立 Mac 近景版：[PlanetGlobePreview-macOS-RegionZoom.zip](../../output/globe_preview/PlanetGlobePreview-macOS-RegionZoom.zip)，支持 Apple 芯片与 Intel。

先前 0.6 倍怪物版本的 Mac 程序：[PlanetGlobePreview-macOS-Universal.zip](../../output/globe_preview/PlanetGlobePreview-macOS-Universal.zip)。此 Mac 包保留原整体缩放，支持 Apple 芯片与 Intel，带 ad-hoc 签名，尚未在真实 Mac 上运行测试。

- 拖动球体：以四元数轨迹球任意转向；鼠标抓住的地表位置跟着指针走。
- 滚轮：从完整球体逐步靠近到局部区域，最远端始终能看见完整球。鼠标放在地表时，尽量保持指针下的区域；缩小时指针落到球外则按中心缩放。复位恢复完整球体。
- 点击怪物：按透明轮廓选中，底部出现选中反馈。
- 底部滑条：12–120 个怪物，默认 36，分布在正反面四个群落。
- 导入怪物：选择本地 PNG / WebP；默认读取 `res://assets/globe_preview/monster_cutout.png`。
- 场景根上的 `monster_texture` 可直接指定贴图；`monster_height` 控制怪物显示高度，默认 45.6（原 76 的 0.6 倍），接地影与选中圈同步缩小。加载时按 alpha ≥ 0.16 的包围盒去除透明余量，脚底对齐地表。文件本身不被修改。
- `closest_camera_distance` 控制最大近景，默认 1.35（单位球半径为 1）；整体观察距离为 3.4。默认最近处球体轮廓半径约为完整视角的 3.58 倍，允许超过窗口边缘来观察局部。

## 实现边界

全部显示使用 Godot 2D 节点与 `canvas_item` shader，没有 Camera3D、MeshInstance3D 或 SubViewport。以固定焦距和变化的观察距离做透视投影；shader 将屏幕射线与单位球相交，再通过 **逆四元数** 获取固定地理位置。怪物则通过 **正四元数** 和同一焦距、距离投影，保持直立 Sprite2D，大小随距离变化，使用局部接地影、球体遮挡与近地平线淡出。

`globe_math.gd` 提供无场景依赖的纯函数：`project_position`、`unproject_position`、`arcball_vector`、`perspective_arcball_vector`、`drag_orientation`、`geographic_position`、`edge_opacity`。坐标约定为 +Y 朝上、+Z 朝向观察者，屏幕 Y 在投影时取反。`camera_distance > 1` 启用透视，`focal_length` 为像素焦距；旧参数调用保留正交数学。反投影仅返回观察者可见的球面帽，球外返回 `Vector3.ZERO`。

第一只怪物在 `normalize(Vector3(-0.37, 0.13, 1.0))`。地表 shader 的金色圈位于同一固定地理位置，可观察旋转时脚底与圈是否始终对齐。地表噪声也在固定地理位置采样，不会随屏幕滑动。

这是视角验证场景，未接入吸取、怪物 AI 或真实地表碰撞。按怪物脚底所在球面点判遮挡，球体遮挡的怪物不接受点击，近地平线的物体按朝向观察者的角度淡出。立绘保持直立，卡通叠层按屏幕 Y 排序。

## 数学参考

实现为按公开数学原创的代码，无第三方 shader 复制。

- [Ken Shoemake — Arcball: A User Interface for Specifying Three-Dimensional Orientation Using a Mouse](https://doi.org/10.1016/B978-0-08-050755-2.50048-4)
- [Godot Quaternion 文档](https://docs.godotengine.org/en/stable/classes/class_quaternion.html)
- [Godot CanvasItem shader 文档](https://docs.godotengine.org/en/stable/tutorials/shaders/shader_reference/canvas_item_shader.html)

默认怪物来自 Notion 草案图片的透明抠图。素材及其源图的出处保存在 `res://assets/globe_preview/README.md`。
