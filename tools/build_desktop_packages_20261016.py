from pathlib import Path
import datetime
import hashlib
import json
import re
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
ENGINE = Path(r"C:\Program Files (x86)\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe")


def run_exports(stage: Path, release: Path, logs: Path, import_label: str = "import") -> None:
    phases = [
        (import_label, ["--editor", "--import", "--quit"]),
        ("windows_export", ["--export-release", "Windows Desktop", str(release / "Windows" / "Planet.exe")]),
        ("macos_export", ["--export-release", "macOS Universal", str(release / "macOS" / "Planet.zip")]),
    ]
    results = {}
    for phase, args in phases:
        print("START " + phase, flush=True)
        with (logs / (phase + ".log")).open("w", encoding="utf-8") as log:
            completed = subprocess.run(
                [str(ENGINE), "--headless", "--path", str(stage), *args],
                cwd=stage, stdout=log, stderr=subprocess.STDOUT,
                timeout=900, creationflags=subprocess.CREATE_NO_WINDOW,
            )
        log_text = (logs / (phase + ".log")).read_text(encoding="utf-8", errors="replace")
        errors = [line for line in log_text.splitlines() if "ERROR:" in line or "Failed to export" in line]
        results[phase] = {"exit_code": completed.returncode, "errors": errors}
        (logs / "export_results.json").write_text(json.dumps(results, ensure_ascii=False, indent=2), encoding="utf-8")
        print(phase + ": " + json.dumps(results[phase], ensure_ascii=False), flush=True)
        if completed.returncode or errors:
            sys.exit(1)
    print("EXPORTS READY", flush=True)


def prepare_export(stage: Path) -> None:
    # Retain currently referenced artwork even when its source still lives in
    # the art library; exclude the library's unused siblings instead.
    required = set()
    for name in ["scripts", "scenes", "resources", "features"]:
        for path in (stage / name).rglob("*"):
            if path.suffix in [".gd", ".tscn", ".tres"]:
                for reference in re.findall(r'res://assets/美术素材库/[^"\n]+', path.read_text(encoding="utf-8")):
                    required.add(stage / reference.removeprefix("res://"))
    required.update(Path(str(path) + ".import") for path in list(required))
    exclusions = []

    def exclude_unused(directory: Path) -> None:
        for path in sorted(directory.iterdir()):
            if any(path == target or path in target.parents for target in required):
                if path.is_dir():
                    exclude_unused(path)
            else:
                exclusions.append(path.relative_to(stage).as_posix() + ("/*" if path.is_dir() else ""))

    exclude_unused(stage / "assets" / "美术素材库")
    preset = stage / "export_presets.cfg"
    text = preset.read_text(encoding="utf-8")
    text = text.replace("assets/美术素材库/*", ",".join(exclusions))
    text = text.replace('application/min_macos_version_x86_64="10.15"', 'application/min_macos_version_x86_64="14.0"')
    text = text.replace('application/min_macos_version_arm64="11.0"', 'application/min_macos_version_arm64="14.0"')
    preset.write_text(text, encoding="utf-8")
    print("Export preset prepared: macOS 14+, " + str(len(required) // 2) + " referenced art-library textures retained", flush=True)


if len(sys.argv) > 1:
    if sys.argv[1] == "--resume":
        previous = json.loads((ROOT / "output" / "latest_build_20261016.json").read_text(encoding="utf-8"))
        run_exports(Path(previous["stage"]), Path(previous["release"]), Path(previous["logs"]), "import_recheck")
    else:
        prepare_export(Path(sys.argv[1]))
    sys.exit(0)


stamp = datetime.datetime.now(datetime.timezone(datetime.timedelta(hours=8))).strftime("%Y%m%d_%H%M%S")
label = "Planet_" + stamp
STAGE = ROOT / "output" / (".build-" + label) / "project"
RELEASE = ROOT / "output" / label
LOGS = ROOT / "artifacts" / (label + "_packages")
for directory in [STAGE, RELEASE / "Windows", RELEASE / "macOS", LOGS]:
    directory.mkdir(parents=True, exist_ok=False)

metadata = {
    "label": label,
    "snapshot_time": datetime.datetime.now(datetime.timezone(datetime.timedelta(hours=8))).isoformat(),
    "source": "current working tree, including local uncommitted changes",
    "base_commit": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip(),
    "stage": str(STAGE),
    "release": str(RELEASE),
    "logs": str(LOGS),
}
(ROOT / "output" / "latest_build_20261016.json").write_text(json.dumps(metadata, ensure_ascii=False, indent=2), encoding="utf-8")
(LOGS / "source_status.txt").write_bytes(subprocess.check_output(["git", "status", "--short"], cwd=ROOT))
print(json.dumps(metadata, ensure_ascii=False), flush=True)

# Snapshot only real project inputs; FMOD searches directories for banks itself.
for name in ["addons", "assets", "bank", "features", "fonts", "resources", "scenes", "scripts", "shaders"]:
    shutil.copytree(ROOT / name, STAGE / name, ignore=shutil.ignore_patterns("~*", "*.tmp"))
for name in ["project.godot", "export_presets.cfg", "icon.svg", "icon.svg.import"]:
    shutil.copy2(ROOT / name, STAGE / name)

manifest = {}
for path in sorted(STAGE.rglob("*")):
    if path.is_file():
        with path.open("rb") as stream:
            manifest[path.relative_to(STAGE).as_posix()] = hashlib.file_digest(stream, "sha256").hexdigest()
(LOGS / "source_sha256.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")
shutil.copytree(ROOT / ".godot" / "imported", STAGE / ".godot" / "imported")
for name in ["extension_list.cfg", "global_script_class_cache.cfg", "uid_cache.bin"]:
    shutil.copy2(ROOT / ".godot" / name, STAGE / ".godot" / name)

# The Windows exporter cannot preserve a macOS framework's relative links.
# Export the same universal FMOD binary as a dylib in this snapshot only.
libraries = STAGE / "addons" / "fmod" / "libs" / "macos"
shutil.copy2(
    libraries / "libGodotFmod.macos.template_release.framework" / "libGodotFmod.macos.template_release",
    libraries / "libGodotFmod.macos.template_release.dylib",
)
extension = STAGE / "addons" / "fmod" / "fmod.gdextension"
extension.write_text(
    extension.read_text(encoding="utf-8").replace(
        'macos.release  = "res://addons/fmod/libs/macos/libGodotFmod.macos.template_release.framework"',
        'macos.release  = "res://addons/fmod/libs/macos/libGodotFmod.macos.template_release.dylib"',
    ),
    encoding="utf-8",
)
assert 'macos.release  = "res://addons/fmod/libs/macos/libGodotFmod.macos.template_release.dylib"' in extension.read_text(encoding="utf-8")
prepare_export(STAGE)
print("Snapshot ready: " + str(len(manifest)) + " source files", flush=True)

run_exports(STAGE, RELEASE, LOGS)
