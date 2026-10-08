# 地面黏液贴图

`blue_ground_mucus.png` 为 1254×1254 RGBA 透明 PNG，使用 Codex 内置生图工具生成，参考用户提供的蓝色黏液巢穴配色与粗手绘线条。保留原始透明通道。此图是旧版滩状方案的素材；用户随后明确要连续带状拖痕，当前效果改用沿真实行走路径生成的三层窄带网格，沿用这张图的深蓝描边、浅蓝黏液和白色湿润高光，不再逐张铺设水滩。

生成提示词：

> Create ONE game-ready transparent sprite of a puddle of sticky blue mucus lying flat on the ground, viewed directly from above. The attached image is STYLE AND PALETTE REFERENCE only: match its bottom row's periwinkle/light-blue goo, dark navy rough hand-drawn outline, chunky simple flat shaded patches and small white painted highlights. Do not reproduce its nests, flowers, words, faces or monsters. Make an asymmetrical connected splat with five or six soft bulging lobes and 3 small nearby droplets, full uneven blue goo silhouette, no perfect ellipse, no ring, no aura, no glow, no magic symbols, no circular border, no ground texture or background. This is a thick liquid surface stain/decal, not a standing blob character or cave. Two or three blue shadow patches and sparse white wavy highlights suggest viscous wet slime. Keep the rough casual hand-drawn 2D game sketch style, not glossy 3D, not vector-clean. Composition: single compact connected puddle centered, fills about 76 percent of square canvas with clear transparent padding, all edges and droplets inside frame. TRUE alpha transparent background. Deliver only the new ground puddle sprite.

参考图保存在 `../nests/nest_species_reference.png`。独立预览入口：`scenes/effects/mucus_field.tscn`。
