"""Stage and export the game with the FMOD HTML5 adapter; invoked by build_web.ps1.

Source scripts stay native. The staging copy substitutes only FMOD handle types
and the FMOD autoload. Assets use hard links; imported caches are never shared.
"""
import argparse
import fnmatch
import json
import os
from pathlib import Path
import re
import shutil
import struct
import subprocess
import zipfile

ROOT = Path(__file__).resolve().parents[1]
TYPES = {
    "FmodEvent": "PlanetWebFmod.Event",
    "FmodEventDescription": "PlanetWebFmod.Description",
    "FmodBank": "PlanetWebFmod.Bank",
    "FmodBus": "PlanetWebFmod.Bus",
    "FmodParameterDescription": "PlanetWebFmod.Parameter",
}
# Full-frame sequences stored lossless today. Creature sheets and UI stay lossless.
FULL_FRAME_LOSSLESS = (
    "assets/场景动画/开头动画/",
    "assets/场景动画/流星/",
)
WEB_LOSSY_QUALITY = "0.85"
TEMPLATE_VERSION = "4.7.2.stable"
# Required minimum MAX_TEXTURE_SIZE in WebGL 2. Larger plates are flagged, not resized.
WEBGL_SAFE_EDGE = 4096


def export_template_dir() -> Path:
    """Official export templates. Windows uses APPDATA; Linux uses the XDG data dir."""
    candidates = []
    if os.environ.get("APPDATA"):
        candidates.append(Path(os.environ["APPDATA"]) / "Godot" / "export_templates" / TEMPLATE_VERSION)
    data_home = Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local/share"))
    candidates.append(data_home / "godot" / "export_templates" / TEMPLATE_VERSION)
    for path in candidates:
        if (path / "web_nothreads_release.zip").is_file():
            return path
    searched = ", ".join(str(path) for path in candidates)
    raise FileNotFoundError("web_nothreads_release.zip not found. Looked in: " + searched)


def image_size(path: Path):
    data = path.read_bytes()[:40]
    if data.startswith(b"\x89PNG\r\n\x1a\n") and data[12:16] == b"IHDR":
        return struct.unpack(">II", data[16:24])
    if data[:4] == b"RIFF" and data[8:12] == b"WEBP" and data[12:16] == b"VP8X":
        width = 1 + int.from_bytes(data[24:27], "little")
        height = 1 + int.from_bytes(data[27:30], "little")
        return width, height
    return None


def bptc_payload(width: int, height: int) -> int:
    """Desktop high-quality VRAM size: one byte per pixel, padded to 4x4 blocks."""
    return ((width + 3) // 4 * 4) * ((height + 3) // 4 * 4)


def apply_web_texture_policy(stage: Path) -> None:
    """Repack staged textures at the source image's pixel size.

    Desktop .import files are not modified. BPTC is about a byte per pixel and
    misses itch.io's 200MB file cap, so the web copy uses Lossy WebP instead.
    An existing size_limit would shrink 近景星球 on import; clear it here so the
    packed texels stay at the PNG dimensions the blend shader names.
    """
    converted = 0
    cleared_limits = 0
    vram_bytes = 0
    oversized = []
    for metadata in stage.rglob("*.import"):
        text = metadata.read_text(encoding="utf-8")
        if 'importer="texture"' not in text:
            continue
        fields = {
            line.split("=", 1)[0]: line.split("=", 1)[1].strip()
            for line in text.splitlines()
            if "=" in line and not line.startswith("[")
        }
        mode = fields.get("compress/mode")
        relative = metadata.relative_to(stage).as_posix().removesuffix(".import")
        source = stage / relative
        size = image_size(source) if source.is_file() else None
        if size and max(size) > WEBGL_SAFE_EDGE:
            oversized.append((size[0], size[1], relative))
        use_lossy = mode == "2" or (mode == "0" and relative.startswith(FULL_FRAME_LOSSLESS))
        if not use_lossy:
            continue
        if "compress/lossy_quality" not in fields or "process/size_limit" not in fields:
            raise ValueError("Unexpected texture import layout: " + relative)
        if mode == "2":
            if size is None:
                raise ValueError("Could not read texture dimensions: " + relative)
            limit = int(fields.get("process/size_limit") or "0")
            width, height = size
            if limit > 0 and max(width, height) > limit:
                scale = limit / max(width, height)
                width = max(1, int(width * scale))
                height = max(1, int(height * scale))
            vram_bytes += bptc_payload(width, height)
        if fields.get("process/size_limit") != "0":
            text = re.sub(r"(?m)^process/size_limit=.*$", "process/size_limit=0", text)
            cleared_limits += 1
        text = re.sub(r"(?m)^compress/mode=.*$", "compress/mode=1", text)
        text = re.sub(r"(?m)^compress/lossy_quality=.*$", "compress/lossy_quality=" + WEB_LOSSY_QUALITY, text)
        metadata.write_text(text, encoding="utf-8")
        converted += 1
    print(
        f"Web textures: {converted} staged imports use Lossy WebP quality {WEB_LOSSY_QUALITY}. "
        f"Source pixel dimensions kept ({cleared_limits} existing size limits cleared). "
        f"Current desktop VRAM payload for those plates: {vram_bytes / 1048576:.1f} MiB.",
        flush=True,
    )
    if oversized:
        print("Full-size textures above WebGL's 4096 minimum edge:", flush=True)
        for width, height, relative in sorted(oversized):
            print(f"  {width}x{height} {relative}", flush=True)


def theme_font_caches(stage: Path) -> list[Path]:
    caches = []
    for metadata in (stage / "fonts").rglob("*.import"):
        for destination in re.findall(r'"res://(\.godot/imported/[^"]+\.fontdata)"', metadata.read_text(encoding="utf-8")):
            caches.append(stage / destination)
    return caches


def seed_theme_fonts(stage: Path, godot: str, log_dir: Path) -> None:
    """The project font is opened before the first import. Create its cache first.

    Copies an existing engine cache when the source tree has one. Otherwise imports
    once with the theme font detached, which is what produces the fontdata files.
    """
    for target in theme_font_caches(stage):
        cached = ROOT / target.relative_to(stage)
        if cached.is_file() and not target.exists():
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(cached, target)
    if all(path.is_file() for path in theme_font_caches(stage)):
        return
    project_path = stage / "project.godot"
    original = project_path.read_text(encoding="utf-8")
    detached = re.sub(r"(?m)^theme/custom_font=.*\n", "", original)
    if detached == original:
        raise RuntimeError("Theme font cache is missing and theme/custom_font was not found")
    project_path.write_text(detached, encoding="utf-8")
    log = log_dir / "web_font_import.log"
    try:
        with log.open("w", encoding="utf-8") as stream:
            result = subprocess.run(
                [godot, "--headless", "--editor", "--path", str(stage), "--import"],
                stdout=stream,
                stderr=subprocess.STDOUT,
                timeout=1800,
            )
        if result.returncode:
            raise RuntimeError(f"Font import failed; see {log}")
    finally:
        project_path.write_text(original, encoding="utf-8")
    missing = [path for path in theme_font_caches(stage) if not path.is_file()]
    if missing:
        raise FileNotFoundError("Theme font cache was not created: " + ", ".join(str(path) for path in missing))
    print(f"Seeded {len(theme_font_caches(stage))} theme fonts before the editor loaded the project font.", flush=True)


def runtime_files(stage: Path) -> list[str]:
    """Include literal dynamic loads as well as scene/resource dependencies.

    Godot's selected-resource export does not see texture page paths stored as
    strings in custom resources. Walk those strings and global script types too.
    Fail on an unresolved path instead of shipping a silently incomplete build.
    """
    classes = {}
    for script in stage.rglob("*.gd"):
        match = re.search(r"^class_name\s+(\w+)", script.read_text(encoding="utf-8"), re.M)
        if match:
            classes[match[1]] = script.relative_to(stage).as_posix()
    pending, found = ["project.godot"], set()
    while pending:
        relative = pending.pop()
        if relative in found:
            continue
        source = stage / relative
        if not source.exists():
            raise FileNotFoundError("Unresolved runtime resource: " + relative)
        found.add(relative)
        if source.is_dir():
            pending.extend(p.relative_to(stage).as_posix() for p in source.rglob("*") if p.is_file() and p.suffix != ".import")
            continue
        if source.suffix not in (".gd", ".tres", ".tscn", ".gdshader", ".gdshaderinc", ".godot"):
            continue
        text = source.read_text(encoding="utf-8")
        pending.extend(re.findall(r'''["'](?:\*)?res://([^"'\n]+)["']''', text))
        for name, script in classes.items():
            if re.search(r"\b" + name + r"\b", text):
                pending.append(script)
        for include in re.findall(r'#include\s+"([^"]+)"', text):
            if not include.startswith("res://"):
                pending.append((source.parent / include).relative_to(stage).as_posix())
    return ["res://" + p for p in sorted(found) if (stage / p).is_file() and p != "project.godot"]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--godot", required=True)
    parser.add_argument("--stage", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--sdk-zip")
    args = parser.parse_args()
    stage, output = Path(args.stage).resolve(), Path(args.output).resolve()
    if not stage.is_relative_to(ROOT / "artifacts") or stage == ROOT / "artifacts":
        raise ValueError("Staging must be a task-owned subdirectory of artifacts")
    stage.mkdir(parents=True, exist_ok=False)
    output.mkdir(parents=True, exist_ok=True)
    (ROOT / "artifacts" / ".gdignore").touch()
    (ROOT / "output").mkdir(exist_ok=True)
    (ROOT / "output" / ".gdignore").touch()
    runtime = ROOT / "web" / "fmod"
    if args.sdk_zip:
        runtime.mkdir(parents=True, exist_ok=True)
        with zipfile.ZipFile(args.sdk_zip) as sdk:
            for name in ("fmodstudio.js", "fmodstudio.wasm"):
                entry = next(n for n in sdk.namelist() if n.endswith("/api/studio/lib/wasm/" + name))
                (runtime / name).write_bytes(sdk.read(entry))
            license_name = next(n for n in sdk.namelist() if n.endswith("/doc/LICENSE.TXT"))
            (runtime / "LICENSE.TXT").write_bytes(sdk.read(license_name))
    if not (runtime / "fmodstudio.wasm").exists():
        raise FileNotFoundError("Supply the FMOD 2.03.06 HTML5 SDK with -SdkZip on the first build")
    presets = (ROOT / "export_presets.cfg").read_text(encoding="utf-8")
    excluded = re.search(r'^exclude_filter="(.*)"', presets, re.M)[1].split(",")
    excluded += ["addons/*", "features/fmod_audio_test/*", "web/*"]
    native_refs = set()
    total = 0
    for folder in ("assets", "bank", "fonts", "features", "scenes", "scripts", "shaders", "resources"):
        source = ROOT / folder
        if not source.exists():
            continue
        for current, dirs, files in os.walk(source):
            current = Path(current)
            if (current / ".gdignore").exists():
                dirs.clear()
                continue
            dirs[:] = [d for d in dirs if not any(fnmatch.fnmatchcase((current / d).relative_to(ROOT).as_posix() + "/", pattern) for pattern in excluded)]
            for name in files:
                src = current / name
                rel = src.relative_to(ROOT).as_posix()
                if any(fnmatch.fnmatchcase(rel, pattern) for pattern in excluded):
                    continue
                dst = stage / rel
                dst.parent.mkdir(parents=True, exist_ok=True)
                if src.suffix == ".gd":
                    text = src.read_text(encoding="utf-8-sig")
                    for old, new in TYPES.items():
                        text = re.sub(r"\b" + old + r"\b", new, text)
                    native_refs.update(re.findall(r"\bFmod[A-Za-z0-9_]+", text))
                    dst.write_text(text, encoding="utf-8")
                elif src.suffix in (".import", ".tscn", ".tres", ".uid"):
                    shutil.copyfile(src, dst)
                else:
                    os.link(src, dst)
                    total += src.stat().st_size
    if native_refs - {"FmodServer"}:
        raise ValueError("Unhandled native FMOD dependencies: " + str(native_refs))
    apply_web_texture_policy(stage)
    adapter_dir = stage / "scripts/platform"
    adapter_dir.mkdir(parents=True, exist_ok=True)
    for adapter in (ROOT / "web/godot").glob("*.gd"):
        shutil.copyfile(adapter, adapter_dir / adapter.name)
    project = (ROOT / "project.godot").read_text(encoding="utf-8")
    project = project.replace('FmodManager="*res://addons/fmod/FmodManager.gd"', 'FmodServer="*res://scripts/platform/web_fmod_server.gd"')
    project = re.sub(r'enabled=PackedStringArray\([^\n]+\)', 'enabled=PackedStringArray()', project)
    project = project.replace('"Forward Plus"', '"GL Compatibility"')
    project = project.replace('[rendering]', '[rendering]\n\nrenderer/rendering_method="gl_compatibility"\nrenderer/rendering_method.mobile="gl_compatibility"')
    project = project.replace(
        "textures/vram_compression/import_etc2_astc=true",
        "textures/vram_compression/import_s3tc_bptc=true\ntextures/vram_compression/import_etc2_astc=false",
    )
    (stage / "project.godot").write_text(project, encoding="utf-8")
    template_dir = export_template_dir()
    with zipfile.ZipFile(template_dir / "web_nothreads_release.zip") as template:
        shell = template.read("godot.html").decode()
    shell = shell.replace('<script src="$GODOT_URL"></script>', '<script src="fmod/fmodstudio.js"></script>\n<script src="planet_fmod.js"></script>\n<script src="$GODOT_URL"></script>')
    shell = shell.replace("engine.startGame({", "PlanetFmod.initialize().then(() => engine.startGame({")
    shell = shell.replace("}).then(() => {\n\t\t\tsetStatusMode('hidden');", "})).then(() => {\n\t\t\tsetStatusNotice('');\n\t\t\tsetStatusMode('notice');\n\t\t\tconst enter = document.createElement('button');\n\t\t\tenter.textContent = '点击进入游戏';\n\t\t\tenter.style.cssText = 'font:inherit;padding:16px 32px;cursor:pointer';\n\t\t\tstatusNotice.appendChild(enter);\n\t\t\tenter.onclick = () => { PlanetFmod.unlock(); setStatusMode('hidden'); document.getElementById('canvas').focus(); };")
    if 'PlanetFmod.initialize' not in shell or 'enter.onclick' not in shell or 'src="fmod/fmodstudio.js"' not in shell:
        raise ValueError("Godot HTML template changed: review the startup hook")
    (stage / "web_shell.html").write_text(shell, encoding="utf-8")
    selected = runtime_files(stage)
    print(f"Selected {len(selected)} runtime resources (including dynamic paths).", flush=True)
    export_files = "PackedStringArray(" + ", ".join(json.dumps(p, ensure_ascii=False) for p in selected) + ")"
    (stage / "export_presets.cfg").write_text('''[preset.0]
name="Web"
platform="Web"
runnable=true
export_filter="resources"
export_files=EXPORT_FILES
include_filter="bank/Desktop/*.bank"
exclude_filter="web_shell.html"

[preset.0.options]
variant/extensions_support=false
variant/thread_support=false
vram_texture_compression/for_desktop=true
vram_texture_compression/for_mobile=false
html/custom_html_shell="res://web_shell.html"
html/canvas_resize_policy=2
html/focus_canvas_on_start=true
progressive_web_app/enabled=false
'''.replace("EXPORT_FILES", export_files), encoding="utf-8")
    print(f"Staged {total / 1048576:.1f} MiB of linked assets (no asset duplication).", flush=True)
    log_dir = stage.parent
    seed_theme_fonts(stage, args.godot, log_dir)
    for label, command in [
        ("import", ["--headless", "--editor", "--import"]),
        ("export", ["--headless", "--export-release", "Web", str(output / "index.html")]),
    ]:
        log = log_dir / ("web_" + label + ".log")
        with log.open("w", encoding="utf-8") as stream:
            result = subprocess.run([args.godot, "--path", str(stage), *command], stdout=stream, stderr=subprocess.STDOUT, timeout=1800)
        text = log.read_text(encoding="utf-8", errors="replace")
        errors = [line for line in text.splitlines() if "SCRIPT ERROR" in line or "Parse Error" in line or "ERROR:" in line]
        print(label, "exit", result.returncode, "errors", len(errors), flush=True)
        if result.returncode or errors:
            print("\n".join(errors[:30]), flush=True)
            raise RuntimeError(f"{label} failed; see {log}")
    shutil.copytree(runtime, output / "fmod", dirs_exist_ok=True)
    for bank in (ROOT / "bank/Desktop").glob("*.bank"):
        shutil.copyfile(bank, output / "fmod" / bank.name)
    shutil.copyfile(ROOT / "web/planet_fmod.js", output / "planet_fmod.js")
    for name in ("serve.py", "start-web.cmd", "README.txt"):
        shutil.copyfile(ROOT / "web" / name, output / name)
    print("Exported", output, flush=True)


if __name__ == "__main__":
    main()
