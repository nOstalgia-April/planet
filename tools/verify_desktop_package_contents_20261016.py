"""Read-only audit of the current Windows PCK and macOS export ZIP.

PCK V2/V3/V4 layout follows Godot's PackedSourcePCK reader:
https://github.com/godotengine/godot/blob/master/core/io/file_access_pack.cpp
This checks package contents and signing structures, not native macOS execution.
"""

from __future__ import annotations

import argparse
import hashlib
import io
import json
import plistlib
import re
import struct
import sys
import zipfile
from dataclasses import dataclass
from pathlib import Path
from typing import BinaryIO


ROOT = Path(__file__).resolve().parent.parent
BANKS = {
    "bank/Desktop/Master.bank",
    "bank/Desktop/Master.strings.bank",
    "bank/Desktop/ProjectVacuum.bank",
}
WINDOWS_LIBS = (
    "fmod.dll",
    "fmodstudio.dll",
    "libGodotFmod.windows.template_release.x86_64.dll",
)
MAC_LIBS = (
    "libfmod.dylib",
    "libfmodstudio.dylib",
    "libGodotFmod.macos.template_release.dylib",
)
RESOURCE_FILES = (
    "resources/mascot/muscle.tres",
    "scenes/ui/mascot_dialogue.tscn",
    "scenes/ui/combo_meter.tscn",
)
CODE_FILES = (
    "scripts/ui/combo_meter.gd",
    "scripts/prototype_run.gd",
    "scripts/disk_demo.gd",
)
CPU_NAMES = {0x01000007: "x86_64", 0x0100000C: "arm64"}


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ValueError(message)


def exact(stream: BinaryIO, length: int) -> bytes:
    data = stream.read(length)
    require(len(data) == length, "Unexpected end of binary file")
    return data


def resource_path(path: str) -> str:
    return path.removeprefix("res://").lstrip("/")


@dataclass(frozen=True)
class Entry:
    offset: int
    size: int
    md5: bytes
    flags: int


class Pck:
    def __init__(self, stream: BinaryIO, size: int) -> None:
        self.stream = stream
        require(exact(stream, 4) == b"GDPC", "Missing standalone PCK magic")
        self.version, major, minor, patch = struct.unpack("<4I", exact(stream, 16))
        self.engine = f"{major}.{minor}.{patch}"
        require(self.version in (2, 3, 4), f"Unsupported PCK version {self.version}")
        flags, file_base = struct.unpack("<IQ", exact(stream, 12))
        require(flags & 1 == 0, "Encrypted PCK directory is unsupported")
        require(flags & 4 == 0, "Sparse PCK is not a standalone distributable")
        if self.version >= 3:
            directory = struct.unpack("<Q", exact(stream, 8))[0]
            require(directory < size, "PCK directory exceeds file size")
            stream.seek(directory)
        else:
            exact(stream, 64)
        count = struct.unpack("<I", exact(stream, 4))[0]
        require(0 < count < 1_000_000, f"Invalid PCK entry count: {count}")
        self.entries: dict[str, Entry] = {}
        for _ in range(count):
            length = struct.unpack("<I", exact(stream, 4))[0]
            require(0 < length < 65_536, "Invalid PCK path length")
            name = resource_path(exact(stream, length).rstrip(b"\0").decode("utf-8"))
            offset, entry_size = struct.unpack("<QQ", exact(stream, 16))
            digest = exact(stream, 16)
            entry_flags = struct.unpack("<I", exact(stream, 4))[0]
            require(entry_flags == 0, f"Unsupported encrypted/removed/delta entry: {name}")
            require(name not in self.entries, f"Duplicate PCK path: {name}")
            require(".." not in name.split("/"), f"Unsafe PCK path: {name}")
            require(file_base + offset + entry_size <= size, f"PCK bounds error: {name}")
            self.entries[name] = Entry(file_base + offset, entry_size, digest, entry_flags)

    def read(self, name: str) -> bytes:
        name = resource_path(name)
        require(name in self.entries, f"Missing packed resource: {name}")
        entry = self.entries[name]
        self.stream.seek(entry.offset)
        data = exact(self.stream, entry.size)
        require(hashlib.md5(data).digest() == entry.md5, f"PCK MD5 mismatch: {name}")
        return data

    def text(self, name: str) -> str:
        return self.read(name).rstrip(b"\0").decode("utf-8").replace("\r\n", "\n")


def verify_pck(pack: Pck, stage: Path) -> dict:
    banks = {name for name in pack.entries if name.endswith(".bank")}
    require(banks == BANKS, f"Wrong bank inventory: {sorted(banks)}")
    leaked = [name for name in pack.entries if name.startswith(("artifacts/", "output/"))]
    require(not leaked, f"Build/artifact files leaked into PCK: {leaked[:10]}")
    for name in sorted(BANKS):
        require(pack.read(name) == (stage / name).read_bytes(), f"Bank differs from snapshot: {name}")

    textures: set[str] = set()
    for name in RESOURCE_FILES:
        content = pack.text(name)
        require(content == (stage / name).read_text(encoding="utf-8").rstrip("\0"), f"Scene/resource differs from snapshot: {name}")
        textures.update(resource_path(path) for path in re.findall(r'path="(res://[^"\n]+\.(?:png|webp))"', content))
    required_raw = {
        f"assets/美术素材库/角色与巢穴/产怪与看板娘补充/看板娘口型2/未命名作品-{index}.png"
        for index in range(7, 13)
    }
    required_raw.add("assets/美术素材库/界面/新增素材/看板娘对话框/IMG_3525.png")
    require(required_raw <= textures, "Seven newly required mascot texture references are incomplete")
    require({"assets/ui/vacuum_progress/frame.png", "assets/ui/vacuum_progress/fill.png"} <= textures, "New vacuum meter artwork is not referenced")
    mapped_textures = []
    for name in sorted(textures):
        imported = pack.text(name + ".import")
        mappings = re.findall(r'^path(?:\.[\w]+)?="(res://[^"\n]+)"', imported, re.MULTILINE)
        require(bool(mappings), f"No imported texture mapping: {name}")
        for mapping in mappings:
            payload = pack.read(mapping)
            require(len(payload) > 32, f"Empty imported texture: {mapping}")
            require(payload == (stage / resource_path(mapping)).read_bytes(), f"Imported texture differs from snapshot: {mapping}")
        mapped_textures.append({"texture": name, "payloads": mappings})

    code = []
    for name in CODE_FILES:
        if name in pack.entries:
            require(pack.text(name) == (stage / name).read_text(encoding="utf-8"), f"Packed script differs: {name}")
            exported = name
        else:
            remap = pack.text(name + ".remap")
            match = re.search(r'^path="(res://[^"\n]+)"', remap, re.MULTILINE)
            require(match is not None, f"Missing script remap: {name}")
            exported = resource_path(match.group(1))
            require(pack.read(exported).startswith(b"GDSC"), f"Invalid compiled GDScript: {exported}")
        code.append({"source": name, "packed": exported, "snapshot_sha256": hashlib.sha256((stage / name).read_bytes()).hexdigest()})
    require("captured_colors" in (stage / CODE_FILES[0]).read_text(encoding="utf-8"), "Snapshot lacks captured-color meter")
    extension = pack.text("addons/fmod/fmod.gdextension")
    require('macos.release  = "res://addons/fmod/libs/macos/libGodotFmod.macos.template_release.dylib"' in extension, "Windows-host macOS dylib export mapping is missing")
    require(pack.text(".godot/extension_list.cfg").strip() == "res://addons/fmod/fmod.gdextension", "Packed GDExtension registration is missing or unexpected")
    return {"pck_version": pack.version, "engine": pack.engine, "entries": len(pack.entries), "banks": sorted(banks), "artifact_paths": len(leaked), "texture_count": len(mapped_textures), "textures": mapped_textures, "code": code}


def pe_machine(path: Path) -> str:
    with path.open("rb") as stream:
        require(exact(stream, 2) == b"MZ", f"Invalid PE file: {path}")
        stream.seek(0x3C)
        offset = struct.unpack("<I", exact(stream, 4))[0]
        stream.seek(offset)
        require(exact(stream, 4) == b"PE\0\0", f"Invalid PE header: {path}")
        machine = struct.unpack("<H", exact(stream, 2))[0]
        require(machine == 0x8664, f"Non-x64 Windows binary: {path}")
        return "x86_64"


def verify_windows(release: Path, stage: Path) -> dict:
    folder = release / "Windows"
    native = {"Planet.exe": pe_machine(folder / "Planet.exe")}
    for name in WINDOWS_LIBS:
        target = folder / name
        native[name] = pe_machine(target)
        require(target.read_bytes() == (stage / "addons/fmod/libs/windows" / name).read_bytes(), f"Windows runtime DLL differs from snapshot: {name}")
    path = folder / "Planet.pck"
    with path.open("rb") as stream:
        result = verify_pck(Pck(stream, path.stat().st_size), stage)
    return {"native": native, "pack": result}


def packed_version(value: int) -> tuple[int, int, int]:
    return value >> 16, (value >> 8) & 255, value & 255


def macho_slices(data: bytes, name: str) -> list[dict]:
    magic, count = struct.unpack_from(">II", data)
    require(magic in (0xCAFEBABE, 0xCAFEBABF), f"Not a universal Mach-O: {name}")
    require(count == 2, f"Expected exactly Intel and Apple Silicon slices: {name}")
    result = []
    for index in range(count):
        if magic == 0xCAFEBABE:
            cpu, _, offset, size, _ = struct.unpack_from(">IIIII", data, 8 + 20 * index)
        else:
            cpu, _, offset, size, _, _ = struct.unpack_from(">IIQQII", data, 8 + 32 * index)
        require(cpu in CPU_NAMES, f"Unexpected Mach-O CPU: {name} {cpu:#x}")
        require(offset + size <= len(data), f"Mach-O slice bounds error: {name}")
        body = memoryview(data)[offset:offset + size]
        require(bytes(body[:4]) == b"\xcf\xfa\xed\xfe", f"Expected little-endian 64-bit Mach-O: {name}")
        commands = struct.unpack_from("<I", body, 16)[0]
        cursor = 32
        minimum = None
        signed = False
        for _ in range(commands):
            command, length = struct.unpack_from("<II", body, cursor)
            require(length >= 8 and cursor + length <= size, f"Invalid Mach-O load command: {name}")
            if command == 0x24:
                minimum = packed_version(struct.unpack_from("<I", body, cursor + 8)[0])
            elif command == 0x32:
                require(struct.unpack_from("<I", body, cursor + 8)[0] == 1, f"Not a macOS Mach-O: {name}")
                minimum = packed_version(struct.unpack_from("<I", body, cursor + 12)[0])
            elif command == 0x1D:
                sign_offset, sign_size = struct.unpack_from("<II", body, cursor + 8)
                require(sign_size > 0 and sign_offset + sign_size <= size, f"Invalid code-signature bounds: {name}")
                signed = True
            cursor += length
        require(minimum is not None and signed, f"Missing minimum-version/signature command: {name}")
        result.append({"architecture": CPU_NAMES[cpu], "minimum_macos": list(minimum), "code_signature_command": signed})
    require({row["architecture"] for row in result} == {"x86_64", "arm64"}, f"Missing universal architecture: {name}")
    return result


def verify_mac(release: Path, stage: Path) -> dict:
    archive_path = release / "macOS/Planet.zip"
    with zipfile.ZipFile(archive_path) as archive:
        names = archive.namelist()
        require(len(names) == len(set(names)), "Duplicate ZIP member names")
        require(all(".." not in name.split("/") for name in names), "Unsafe ZIP member path")
        plist_names = [name for name in names if name.endswith(".app/Contents/Info.plist")]
        require(len(plist_names) == 1, "Expected one application bundle")
        prefix = plist_names[0].removesuffix("Info.plist")
        plist = plistlib.loads(archive.read(plist_names[0]))
        minimum = plist.get("LSMinimumSystemVersionByArchitecture", {})
        for architecture in ("x86_64", "arm64"):
            version = tuple(int(part) for part in minimum.get(architecture, "0").split("."))
            require(version >= (14, 0), f"Application advertises unsupported macOS version: {architecture} {version}")
        native = {}
        native_names = ["MacOS/" + plist["CFBundleExecutable"]] + ["Frameworks/" + name for name in MAC_LIBS]
        for name in native_names:
            info = archive.getinfo(prefix + name)
            require((info.external_attr >> 16) & 0o111 != 0, f"Executable permission missing: {name}")
            slices = macho_slices(archive.read(info), name)
            for row in slices:
                declared = tuple(int(part) for part in minimum[row["architecture"]].split("."))
                declared = (declared + (0, 0, 0))[:3]
                require(tuple(row["minimum_macos"]) <= declared, f"Native binary requires newer macOS than Info.plist: {name}")
            native[name] = slices
        signing = plistlib.loads(archive.read(prefix + "_CodeSignature/CodeResources"))
        signed_files = signing.get("files2", {})
        for name in native_names[1:] + ["Resources/Planet.pck"]:
            require(name in signed_files, f"CodeResources entry missing: {name}")
        pack_bytes = archive.read(prefix + "Resources/Planet.pck")
        pck_hash = signed_files["Resources/Planet.pck"].get("hash2")
        require(pck_hash == hashlib.sha256(pack_bytes).digest(), "CodeResources PCK SHA256 mismatch")
        result = verify_pck(Pck(io.BytesIO(pack_bytes), len(pack_bytes)), stage)
        del pack_bytes
        require(archive.testzip() is None, "ZIP member CRC mismatch")
        return {"archive": str(archive_path), "minimum_macos": minimum, "native": native, "code_resources": True, "pck_signed_hash": True, "zip_crc": True, "pack": result, "native_mac_execution": "not performed on this Windows host"}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--metadata", type=Path, default=ROOT / "output/latest_build_20261016.json")
    parser.add_argument("--windows-only", action="store_true")
    args = parser.parse_args()
    metadata = json.loads(args.metadata.read_text(encoding="utf-8"))
    release, stage = Path(metadata["release"]), Path(metadata["stage"])
    report = {"label": metadata["label"], "release": str(release), "passed": False}
    try:
        report["windows"] = verify_windows(release, stage)
        if not args.windows_only:
            report["macos"] = verify_mac(release, stage)
        report["passed"] = True
    except (ValueError, OSError, KeyError, struct.error, zipfile.BadZipFile) as error:
        report["error"] = str(error)
    print(json.dumps(report, ensure_ascii=False, indent=2))
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    sys.exit(main())
