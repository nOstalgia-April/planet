"""Pack the AE core sequence into small, independently loadable WebP atlases.

Usage: python tools/pack_planet_core.py SOURCE_DIRECTORY
Requires Pillow. Originals are read-only; frame timing survives deduplication.
"""

import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
DEST = ROOT / "assets/场景动画/星球核心"
RESOURCE_ROOT = "res://assets/场景动画/星球核心"
COLUMNS, ROWS = 8, 8
QUALITY = 55
PADDING = 4


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    args = parser.parse_args()
    files = sorted(args.source.glob("*.png"))
    if not files:
        raise SystemExit("No PNG sequence found")
    unique, frame_tiles, seen = [], [], {}
    bounds = None
    size = None
    for frame, path in enumerate(files):
        if int(path.stem.rsplit("_", 1)[1]) != frame:
            raise ValueError("Expected continuous zero-based frame numbers")
        digest = hashlib.sha256(path.read_bytes()).digest()
        if digest not in seen:
            seen[digest] = len(unique)
            unique.append(path)
            with Image.open(path) as image:
                if size is None:
                    size = image.size
                if image.mode != "RGBA" or image.size != size:
                    raise ValueError("Expected equally sized RGBA frames")
                box = image.getchannel("A").getbbox()
                if box:
                    bounds = box if bounds is None else (
                        min(bounds[0], box[0]), min(bounds[1], box[1]),
                        max(bounds[2], box[2]), max(bounds[3], box[3]),
                    )
        frame_tiles.append(seen[digest])
    if bounds is None:
        raise ValueError("Sequence is entirely transparent")
    left, top = bounds[0] - PADDING, bounds[1] - PADDING
    width = ((bounds[2] - left + PADDING + 3) // 4) * 4
    height = ((bounds[3] - top + PADDING + 3) // 4) * 4
    crop = (left, top, left + width, top + height)
    DEST.mkdir(parents=True, exist_ok=True)
    per_page = COLUMNS * ROWS
    page_count = (len(unique) + per_page - 1) // per_page

    def pack(page):
        atlas = Image.new("RGBA", (width * COLUMNS, height * ROWS))
        for tile, path in enumerate(unique[page * per_page:(page + 1) * per_page]):
            with Image.open(path) as source:
                atlas.paste(source.crop(crop), (tile % COLUMNS * width, tile // COLUMNS * height))
        name = f"core_{page:03d}.webp"
        atlas.save(DEST / name, "WEBP", quality=QUALITY, method=6)
        source_path = f"{RESOURCE_ROOT}/{name}"
        suffix = hashlib.md5(source_path.encode()).hexdigest()
        imported = f"res://.godot/imported/{name}-{suffix}.ctex"
        # Lossy import prioritizes export size; no mipmaps for this flat effect.
        (DEST / (name + ".import")).write_text(
            '[remap]\n\nimporter="texture"\ntype="CompressedTexture2D"\n'
            f'path="{imported}"\nmetadata={{\n"vram_texture": false\n}}\n\n'
            f'[deps]\n\nsource_file="{source_path}"\ndest_files=["{imported}"]\n\n'
            '[params]\n\ncompress/mode=1\ncompress/high_quality=false\n'
            'compress/lossy_quality=0.55\ncompress/hdr_compression=1\n'
            'compress/normal_map=0\ncompress/channel_pack=0\nmipmaps/generate=false\n'
            'process/fix_alpha_border=true\nprocess/premult_alpha=false\n'
            'process/size_limit=0\ndetect_3d/compress_to=0\n', encoding="utf-8",
        )
        return name

    print(f"Packing {len(files)} frames / {len(unique)} unique, crop {crop}, {page_count} pages", flush=True)
    with ThreadPoolExecutor(max_workers=4) as pool:
        names = list(pool.map(pack, range(page_count)))
    paths = ", ".join(json.dumps(f"{RESOURCE_ROOT}/{name}", ensure_ascii=False) for name in names)
    tiles = ", ".join(map(str, frame_tiles))
    (DEST / "sequence.tres").write_text(
        '[gd_resource type="Resource" script_class="PlanetCoreClip" load_steps=2 format=3]\n\n'
        '[ext_resource type="Script" path="res://scripts/planet_core_clip.gd" id="1"]\n\n'
        '[resource]\nscript = ExtResource("1")\n'
        f'page_paths = PackedStringArray({paths})\nframe_tiles = PackedInt32Array({tiles})\n'
        f'tile_size = Vector2i({width}, {height})\ncolumns = {COLUMNS}\nrows = {ROWS}\n'
        f'pivot = Vector2({size[0] / 2 - left}, {size[1] / 2 - top})\n', encoding="utf-8",
    )
    report = dict(
        source_directory=str(args.source.resolve()), source_frames=len(files),
        unique_frames=len(unique), source_size=size, alpha_bounds=bounds, crop=crop,
        tile_size=[width, height], columns=COLUMNS, rows=ROWS, pages=page_count,
        webp_quality=QUALITY, godot_lossy_quality=0.55,
        source_bytes=sum(f.stat().st_size for f in files),
        atlas_bytes=sum((DEST / name).stat().st_size for name in names),
        timing="30 fps: 2928 changing frames = 97.6 seconds; current FMOD Mx_GamePlay = 97.627 seconds. Full source with static tail = 120 seconds.",
    )
    (DEST / "provenance.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report, ensure_ascii=False), flush=True)


if __name__ == "__main__":
    main()
