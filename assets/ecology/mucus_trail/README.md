# 黏液怪移动轨迹

2026-10-17：正式游戏与黏液扩散预览已切回 `mucus_field_legacy.tscn`，使用原 `008.png` 与 `mucus_trail.gdshader`。下面两张新素材暂保留在独立的 `mucus_field.tscn` 中，供比较。

新素材方案使用用户于 2026-10-16 提供的两张透明 PNG，原文件直接复制，没有抠图或重绘：

- `blue_strip.png`：`未命名作品-2.png`，长条主体沿移动路径铺开。
- `blue_tail.png`：`未命名作品-1.png`，短图的圆润左端用于远离怪物的尾端，在 12 个世界单位内平滑衔接主体。

两张原始图片均完整保留。材质根据距尾端的路径长度，在圆头和连续长条之间过渡，不再去白；每条轨迹独立传递采样偏移，保留主体笔触的位置。尾部轮廓也用于接触判定；最大长度边界在采样段内插值，避免整段删点造成跳动。扩散、寿命、地表裁切继续沿用。

短图内部颜料的原始 alpha 为 154，长图为 255；材质仅将短图的不透明度乘以 255/154，匹配拼接处浓度，透明背景仍然透明，磁盘原图未修改。

`blue_brush_reference.jpg` 是此前白底试用图，当前场景已不引用。

- 新素材独立方案：`res://scenes/effects/mucus_field.tscn`
- 当前正式使用的旧方案：`res://scenes/effects/mucus_field_legacy.tscn`，保留原 `008.png` 素材和 `mucus_trail.gdshader`。
- 回退：将 `scenes/disk_demo.tscn` 中 `29_mucus` 的路径改为旧方案；或在 DiskDemo 检查器的 `mucus_scene` 指定旧场景。预览若也要回退，替换 `features/mucus_spread_preview/mucus_spread_preview.gd` 中 `TRAIL_SCENE` 的路径。

两个轨迹场景均可独立运行查看笔触，地表接入可运行 `res://features/mucus_spread_preview/mucus_spread_preview.tscn`。
