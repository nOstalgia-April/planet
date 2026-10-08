# 整球总览独立贴图

`gray_planet.png` 只用于滚轮切换后的整球总览；近景继续使用可调整的地壳绘制。参考为用户提供的灰色／黑色星球图，存于 `docs/references/planet-overview-texture-reference.png`。用户确认本轮只换贴图，数量气泡和背景变色未加入。

贴图使用内置 imagegen 生成，外部为透明 alpha，中央黑色区域保持不透明；接入 `scenes/world/planet_surface.tscn` 的 `overview_texture`。图案随星球角度旋转，活动范围和收集仍使用真实地壳边界。

最终提示词：

Use case: background-extraction / precise-object-edit. Asset type: transparent PNG sprite for a game's zoomed-out planet overview. Edit target: attached four-panel reference sheet. Extract ONLY the gray-and-black planet from the TOP, monochrome panel and redraw it cleanly at high resolution. Preserve the reference's irregular circular silhouette, gray charcoal hand-drawn continent/rock patches surrounding a very dark BLACK opaque central area, sketchy uneven ink outlines, small craggy rock protrusions, and sparse jagged white/gray details at the rim. Keep the silhouette circular and viewed head-on, with a naturally asymmetrical mottled charcoal surface. The black center is SOLID opaque black, not a transparent hole. Deliver ONE isolated complete round planet centered, filling about 92% of a square canvas with small transparent margin around all protrusions. True transparent alpha outside the planet. Do NOT include surrounding space background, orbiting debris, colored zones, color splats, monster bubbles, captions, Chinese text, UI, glow backdrop, borders, panels, or the lower three planets. Do not make it photorealistic or a smooth 3D ball; match the flat hand-painted gray/black drawing of the top panel.
