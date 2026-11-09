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
    adapter_dir = stage / "scripts/platform"
    adapter_dir.mkdir(parents=True, exist_ok=True)
    for adapter in (ROOT / "web/godot").glob("*.gd"):
        shutil.copyfile(adapter, adapter_dir / adapter.name)
    # The project theme loads before the editor's first import pass. Seed just
    # its font data (copies, never hard links to the editable engine cache).
    for metadata in (stage / "fonts").rglob("*.import"):
        for destination in re.findall(r'"res://(\.godot/imported/[^\"]+\.fontdata)"', metadata.read_text(encoding="utf-8")):
            cached = ROOT / destination
            if cached.exists():
                target = stage / destination
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(cached, target)
    project = (ROOT / "project.godot").read_text(encoding="utf-8")
    project = project.replace('FmodManager="*res://addons/fmod/FmodManager.gd"', 'FmodServer="*res://scripts/platform/web_fmod_server.gd"')
    project = re.sub(r'enabled=PackedStringArray\([^\n]+\)', 'enabled=PackedStringArray()', project)
    project = project.replace('"Forward Plus"', '"GL Compatibility"')
    project = project.replace('[rendering]', '[rendering]\n\nrenderer/rendering_method="gl_compatibility"\nrenderer/rendering_method.mobile="gl_compatibility"')
    (stage / "project.godot").write_text(project, encoding="utf-8")
    template_dir = Path(os.environ["APPDATA"]) / "Godot/export_templates/4.7.2.stable"
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
    for label, command in [
        ("import", ["--headless", "--editor", "--import"]),
        ("export", ["--headless", "--export-release", "Web", str(output / "index.html")]),
    ]:
        log = log_dir / ("web_" + label + ".log")
        with log.open("w", encoding="utf-8") as stream:
            result = subprocess.run([args.godot, "--path", str(stage), *command], stdout=stream, stderr=subprocess.STDOUT, timeout=900)
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
