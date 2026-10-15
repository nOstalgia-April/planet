# 主菜单氛围参考 · 2026-10-15

本次针对正式标题菜单 `scenes/主菜单/主菜单.tscn`。构图与颜色依据正式素材 `assets/场景动画/主菜单/封面.png`：不透明黑底、灰色手绘星球、玫红外圈和中央白色标题。未以历史 `artifacts/` 截图作为当前画面依据。

## 《杀戮尖塔 2》参考

- 官方来源：[Mega Crit，The Neowsletter — January 2025](https://megacrit.com/news/2025-1-15-neowsletter-issue-6/)。官方称其为主菜单背景截帧。
- [官方 4K 图片](https://megacrit.com/images/sts2_mainmenu_4k.jpg) 已在浏览器中实际查看，未下载或引入项目。
- 静帧可观察到稀疏青色光点、集中于右上云洞和塔窗的暖色光源、低对比灰蓝远景，以及暗云形成的自然框景。视觉焦点来自局部明暗和前后层次。
- 静帧不能证明光点的运动方式、动画速度或具体 shader 实现。以下动态设计属于本项目的设计选择，不是对原作技术实现的断言。

## 本项目处理方向

保留正式封面的构图和主色。沿现有玫红外圈增加低频呼吸光；少量微粒以不同尺寸、透明度和速度表达近远层次；暗角轻压边缘，保留中央白色标题和左下按钮的辨识度。

初始调参建议：呼吸周期约 8–14 秒，亮度变化维持小幅；粒子缓慢漂移，避免覆盖整屏的强亮点；暗角强度可从 0.12–0.20 范围试调，以真实运行画面为准。底图已有黑边，不能仅靠增加暗角强度判断改进。使用黑紫或黑红的边缘色，让新增表现延续玫红色系。

## 暗角 shader 来源

- 标题：[Vignette](https://godotshaders.com/shader/vignette-3/)
- 作者：Lu；发布日期：2024-12-22。
- 许可：CC0。网页正文明确声明代码及代码片段适用 CC0；网页中的图像和视频不在该许可范围内，本项目未使用这些媒体。
- 类型：`canvas_item`，源码首行为 `shader_type canvas_item;`，网页含 `4.x` 标签。
- 原算法通过 UV 到中心的距离控制透明度，提供半径、透明度和颜色参数，不读取屏幕纹理。适合改为带中心保护区的柔和 `smoothstep` 暗角。
- 核查方式：已按 `godotshaders-scout` 技能执行 `fetch_godotshader_post.py <url> --json`，但本机请求返回 HTTP 455，未能取得 `license_slug` / `shader_type_slug` taxonomy。作者、CC0 声明及类型通过来源网页正文和源码独立核实；未伪造脚本提取结果。

## F6 对比入口

打开 `features/shader_gallery/menu_atmosphere_shader_gallery.tscn` 并按 F6。右上选择器提供“原图”“仅氛围光”“完整效果”，默认完整效果。预览直接实例化正式菜单，切换其 `画布/Atmosphere` 中的表现节点，不维护另一份封面或正式菜单布局。

## 已接入的表现与调整入口

正式菜单只新增 `画布/Atmosphere`，位于封面后、中文标题和按钮前。表现独立保存在 `scenes/effects/menu_atmosphere.tscn`，与菜单加载、音乐和场景跳转无状态耦合；移除表现不影响菜单功能。全部 Control 层忽略鼠标输入，沿菜单既有 1920×1080 画布一起缩放并裁剪。

| 部件 | 当前参数 | 调整入口 |
| --- | --- | --- |
| 玫红光环与紫红空气层 | 12 秒呼吸，强度 0.38，保留静态细颗粒 | `AmbientGlow` 的 ShaderMaterial，`shaders/menu_ambient_glow.gdshader` |
| 远处星尘 | 64 颗，19 秒寿命，5–13 像素/秒，柔和淡入淡出 | `FarMotes` 粒子节点 |
| 近处失焦微粒 | 13 颗，24 秒寿命，8–16 像素/秒，较低透明度 | `NearMotes` 粒子节点 |
| 柔和暗角 | 强度 0.20，中央标题横带受保护 | `Vignette` 的 ShaderMaterial，`shaders/godotshaders/menu_atmosphere/variant_1_soft_vignette.gdshader` |

暗角基于上述 Lu 的 CC0 径向思路改写。光环与粒子 shader 为本项目编写；没有复制参考游戏的素材。粒子采用独立节点和单个简单材质，没有读屏、折射、全屏模糊或新增光照管线。

## 本次实机验证

2026-10-15 使用 Godot 4.7.2、Vulkan Forward+、RTX 4060 实际运行正式主菜单。本次改动前后的截图保存在 `artifacts/menu_atmosphere_20261015/`。已查看 1920×1080 与 1280×800 的新画面和预览展开状态，核对标题、菜单位置、边界和黑边；间隔两秒的图像确认表现持续变化，真实鼠标输入确认预览可开关。菜单提前开始、重复点击、加载失败重试、离开/返回和共享预加载交接的原有检查通过。

截图工具退出时存在改动前就有的资源释放提示（38 resources、1 shader、3 fonts；改动后纹理计数从 22 到 24），运行期间没有新的脚本或 shader 编译错误。未将这些提示表述为全工程无错误。

F6 对比场景已使用相同图形后端实际启动，退出码 0。新增脚本通过 `gdformat --check`，保留 `tests/.gdignore` 与 `tools/.gdignore`。

因为原工程编辑器正由用户打开，`tools/check_editor_startup.ps1` 的原工程检查按保护规则拒绝运行，未关闭该编辑器。随后在当前工程的独立文件副本中运行同一脚本，保留原布局、资源缓存和 Forward+ 后端，三轮均通过：每轮 35/35 已保存场景和当前场景完成加载，脚本文档缓存重新生成，编辑器退出码均为 0。日志保留在 `artifacts/menu_atmosphere_editor_20261015_204819_641/validation/`；约 2 GB 的临时副本在验证完成后清理。
