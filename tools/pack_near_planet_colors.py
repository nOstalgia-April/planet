"""Pack supplied large-planet layers without resizing or recoloring.

Usage: python tools/pack_near_planet_colors.py SOURCE_DIRECTORY
Requires Pillow. The shared crop preserves pixel alignment with the near globe.
"""

import argparse
import hashlib
import json
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
DEST = ROOT / "assets/场景动画/星球复色/近景高清"
SOURCE_SIZE = (8119, 7866)
# Include two transparent pixels around the union of all source bounds.
CROP = (1069, 806, 7018, 6507)
GROUPS = {
    "pink": ["IMG_3040-7.png", "IMG_3040-9.png", "IMG_3040-1 3.png"],
    "blue": ["IMG_3040-3.png", "IMG_3040-4.png", "IMG_3040-8.png", "IMG_3040-10.png"],
    "green": ["IMG_3040-1.png", "IMG_3040-2.png", "IMG_3040-2 2.png", "IMG_3040-5.png", "IMG_3040-6.png"],
}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    args = parser.parse_args()
    DEST.mkdir(parents=True, exist_ok=True)
    hashes = {}

    def read(name):
        path = args.source / name
        hashes[name] = hashlib.sha256(path.read_bytes()).hexdigest()
        with Image.open(path) as image:
            if image.size != SOURCE_SIZE or image.mode != "RGBA":
                raise ValueError(f"Unexpected source format: {name}")
            return image.crop(CROP)

    restored = read("IMG_3040-1 2.png")
    for name, sources in GROUPS.items():
        layer = Image.new("RGBA", restored.size)
        for source in sources:
            layer.alpha_composite(read(source))
        layer.save(DEST / f"{name}.png")
        restored.alpha_composite(layer)
    restored.save(DEST / "restored.png")
    for name in [*GROUPS, "restored"]:
        resource = f"res://{(DEST / (name + '.png')).relative_to(ROOT).as_posix()}"
        suffix = hashlib.md5(resource.encode()).hexdigest()
        imported = f"res://.godot/imported/{name}.png-{suffix}.ctex"
        (DEST / f"{name}.png.import").write_text(
            f'''[remap]

importer="texture"
type="CompressedTexture2D"
path="{imported}"

[deps]

source_file="{resource}"
dest_files=["{imported}"]

[params]

compress/mode=2
compress/high_quality=true
mipmaps/generate=true
process/fix_alpha_border=true
process/size_limit=0
detect_3d/compress_to=0
''', encoding="utf-8"
        )
    (DEST / "sources.json").write_text(json.dumps({
        "source_size": SOURCE_SIZE,
        "crop": CROP,
        "groups": GROUPS,
        "restored_base": "IMG_3040-1 2.png",
        "near_uv_to_source_uv": ["1 - v", "u"],
        "sha256": hashes,
    }, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"Packed four {restored.width}x{restored.height} textures at original pixel density.")


if __name__ == "__main__":
    main()
