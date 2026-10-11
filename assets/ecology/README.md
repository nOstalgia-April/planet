# 地面黏液贴图

`blue_ground_mucus.png` 为 1254×1254 RGBA 透明 PNG，使用 Codex 内置生图工具生成，参考用户提供的蓝色黏液巢穴配色与粗手绘线条。保留原始透明通道。此图是旧版滩状方案的素材，当前滑行拖痕使用下方的爬行黏液提取图。

生成提示词：

> Create ONE game-ready transparent sprite of a puddle of sticky blue mucus lying flat on the ground, viewed directly from above. The attached image is STYLE AND PALETTE REFERENCE only: match its bottom row's periwinkle/light-blue goo, dark navy rough hand-drawn outline, chunky simple flat shaded patches and small white painted highlights. Do not reproduce its nests, flowers, words, faces or monsters. Make an asymmetrical connected splat with five or six soft bulging lobes and 3 small nearby droplets, full uneven blue goo silhouette, no perfect ellipse, no ring, no aura, no glow, no magic symbols, no circular border, no ground texture or background. This is a thick liquid surface stain/decal, not a standing blob character or cave. Two or three blue shadow patches and sparse white wavy highlights suggest viscous wet slime. Keep the rough casual hand-drawn 2D game sketch style, not glossy 3D, not vector-clean. Composition: single compact connected puddle centered, fills about 76 percent of square canvas with clear transparent padding, all edges and droplets inside frame. TRUE alpha transparent background. Deliver only the new ground puddle sprite.

参考图保存在 `../nests/nest_species_reference.png`。独立预览入口：`scenes/effects/mucus_field.tscn`。

## 爬行黏液替换（2026-10-11）

`crawl_mucus_strip.png` 为 2172×724 RGBA 透明 PNG，使用 Codex 内置 image_gen 编辑工具，从 `assets/场景动画/黏液怪移动/006.png` 提取角色右侧的亮蓝色地面黏液。原爬行序列保留。生成式提取保留原配色与笔触，输出不是逐像素裁切。

正式滑行效果沿真实路径铺设此贴图，使用中间连续区域并镜像衔接，隐藏旧色带的装饰层。贴地裁切、接触范围、长度上限、尾部消退及离屏更新继续使用现有规则。`texture_length` 可在黏液拖痕场景检查器调整纹理延展长度；取图区域位于 `shaders/mucus_trail.gdshader` 的 `source_region`。

最终编辑提示词（内置工具，透明背景）：

> Use case: background-extraction. Asset type: game slime trail texture. Extract ONLY the low, horizontal cobalt blue mucus smear trailing along the floor to the RIGHT of the crawling pale-blue slime monster in the attached existing sprite. Remove the monster completely, including its face, eyes, body, foot and its black outline. Keep the original smear's exact cobalt blue colors, simple flat 2D hand drawn uneven upper and lower edge and small light-blue strokes. Do not redesign it, do not add gloss, gradients, navy borders, droplets, shadows or any new art. Keep the smear a thin long horizontal strip with its width roughly 8 times its height, centered on a truly alpha transparent canvas with tight transparent padding. The left edge should continue naturally as a blue flat trail where it was underneath the monster. The only opaque pixels should be the blue ground smear. No character, no background, no text.

Godot 4.7.2 已通过现有黏液离屏／接触／消退检查与地面生态检查，并查看 1920×1080、1280×800 的游戏截图。检查副本改用场景入口以加载项目音频单例，输出保存在 `artifacts/crawl_mucus_check/`。本机 gdformat 不支持原有带类型循环，格式检查使用去除循环类型标注的副本。
