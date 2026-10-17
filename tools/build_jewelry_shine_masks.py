"""Rebuild the imported masks and frame sets used by jewelry_shine.tscn.

Requires Pillow, NumPy and SciPy. Uses the supplied jewelry layers as the metal
palette; the original animation PNGs remain unchanged. No runtime image analysis.
"""

from pathlib import Path

import numpy as np
from PIL import Image
from scipy import ndimage
from scipy.spatial import cKDTree

ROOT = Path(__file__).resolve().parents[1]
ART = ROOT / "assets/物品动画/高价值怪物"
OUTPUT = ROOT / "assets/effects/jewelry_shine"
RESOURCES = ROOT / "resources/jewelry_shine"
SPECIES = {"史莱姆": "slime", "黏液怪": "mucus", "地鼠": "mole"}


def metal_palette(species):
    reference = np.array(Image.open(OUTPUT / "source_layers" / f"{species}.png").convert("RGBA"))
    rgb = reference[:, :, :3].astype(float)
    gold = (
        (reference[:, :, 3] > 100)
        & (rgb[:, :, 0] > 80)
        & (rgb[:, :, 1] > 60)
        & (rgb[:, :, 1] > rgb[:, :, 2] * 1.2)
        & (rgb[:, :, 0] > rgb[:, :, 2] * 1.3)
    )
    colors, counts = np.unique(rgb[gold], axis=0, return_counts=True)
    return cKDTree(colors[counts >= 20])


def mask_for(image, species, palette, idle):
    pixels = np.array(image.convert("RGBA"))
    rgb = pixels[:, :, :3].astype(float)
    distance = palette.query(rgb.reshape(-1, 3))[0].reshape(pixels.shape[:2])
    mask = (
        (pixels[:, :, 3] > 16)
        & (distance < 18)
        & (rgb[:, :, 0] > 75)
        & (rgb[:, :, 1] > 55)
    )
    if species == "地鼠":
        body_colors = cKDTree(np.array([
            [255, 198, 58], [255, 246, 198], [255, 170, 6], [102, 56, 31],
            [192, 117, 49], [255, 255, 255], [154, 181, 131], [0, 0, 0],
        ], float))
        body_distance = body_colors.query(rgb.reshape(-1, 3))[0].reshape(pixels.shape[:2])
        mask &= distance + 0.2 < body_distance
        if idle:
            # Preserve the approved idle preview pixel-for-pixel.
            yy, xx = np.indices(pixels.shape[:2])
            mask &= (yy > 320) & (yy < 810) & (xx > 250) & (xx < 1000)
        seed = (
            (rgb[:, :, 0] > 230) & (rgb[:, :, 1] > 195)
            & (rgb[:, :, 1] < 235) & (rgb[:, :, 2] < 45) & mask
        )
        connected, _ = ndimage.label(ndimage.binary_dilation(mask, iterations=2))
        labels = np.unique(connected[seed])
        mask &= np.isin(connected, labels[labels > 0])
    return Image.fromarray(np.where(mask, pixels[:, :, 3], 0).astype(np.uint8))


def res_path(path):
    return "res://" + path.relative_to(ROOT).as_posix()


def build():
    RESOURCES.mkdir(parents=True, exist_ok=True)
    for species, slug in SPECIES.items():
        palette = metal_palette(species)
        entries = []
        for source in sorted((ART / species).rglob("*.png")):
            mask = mask_for(Image.open(source), species, palette, source.parent.name == "待机")
            bounds = mask.getbbox()
            if bounds is None:
                print("No jewelry:", source.relative_to(ART))
                continue
            left, top, right, bottom = bounds
            # One zero pixel on every edge preserves the full-size mask's filtering.
            region = (left - 1, top - 1, right + 1, bottom + 1)
            target = OUTPUT / slug / source.relative_to(ART / species)
            target.parent.mkdir(parents=True, exist_ok=True)
            mask.crop(region).save(target)
            entries.append((source, target, region))
        lines = [f'[gd_resource type="Resource" load_steps={2 + len(entries) * 2} format=3]', "",
                 '[ext_resource type="Script" path="res://scripts/effects/jewelry_shine_frames.gd" id="1"]']
        for i, (source, mask, _) in enumerate(entries):
            lines += [f'[ext_resource type="Texture2D" path="{res_path(source)}" id="s{i}"]',
                      f'[ext_resource type="Texture2D" path="{res_path(mask)}" id="m{i}"]']
        lines += ["", "[resource]", 'script = ExtResource("1")',
                  "masks = Dictionary[Texture2D, Texture2D]({"]
        lines += [f'ExtResource("s{i}"): ExtResource("m{i}")' + ("," if i + 1 < len(entries) else "")
                  for i in range(len(entries))]
        lines += ["})", "regions = Dictionary[Texture2D, Rect2]({"]
        for i, (_, _, (left, top, right, bottom)) in enumerate(entries):
            lines += [f'ExtResource("s{i}"): Rect2({left}, {top}, {right-left}, {bottom-top})'
                      + ("," if i + 1 < len(entries) else "")]
        lines += ["})", ""]
        (RESOURCES / f"{slug}.tres").write_text("\n".join(lines), encoding="utf-8")
        print(species, len(entries), "masks")


if __name__ == "__main__":
    build()
