"""Archive delivered art without changing runtime resources; build a local catalog.

Usage: python tools/organize_art_library.py [--source-base PATH] [--reference-base PATH]
Re-running verifies existing copies and refuses to overwrite different content.
"""
from __future__ import annotations

import argparse
from collections import defaultdict
from datetime import datetime
import hashlib
import json
from pathlib import Path
import re
import shutil
from zoneinfo import ZoneInfo

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
LIB = ROOT / 'assets/美术素材库'
REPORT = ROOT / 'docs/art_inventory'
DEFAULT_BASE = Path(r'C:\Users\ROG\Documents\xwechat_files\wxid_n7y8raitb6rf22_a015\msg\file\2026-10')
DEFAULT_REF = Path(r'C:\Users\ROG\Documents\xwechat_files\wxid_n7y8raitb6rf22_a015\temp\RWTemp\2026-10\575ff40aeee6797f89df30b6e038e399')
PACKS = [
    ('A物品动画', 'A物品动画', '角色与巢穴/基础动画'),
    ('补充部分', '补充部分', '角色与巢穴/产怪与看板娘补充'),
    ('地鼠花修改', '地鼠花修改', '角色与巢穴/地鼠花修改版'),
    ('怪兽补充', '怪兽补充', '角色与巢穴/高清怪兽补充'),
    ('合成 1(1)', '合成 1', '场景/星球核心原始序列'),
    ('开头动画(1)', '开头动画', '开场与演出/开头动画'),
    ('科技树', '科技树', '界面/科技树'),
    ('小粉气泡', '小粉气泡', '界面/小粉气泡'),
    ('新增的', '', '界面/新增素材'),
    ('星球清扫计划（场景部分）', '星球清扫计划（场景部分）', '场景/场景原画与动画'),
]
REFS = {
    '0878ec8a9dde462c5701e3f9f37514c7.png': '科技树配色参考_红.png',
    'dbba03cd2c59d088aaabb3d018c3a12d.png': '科技树配色参考_绿.png',
    'cf4a8bf736fe9317712ce71f4a448309.png': '科技树配色参考_蓝.png',
    'cc269591ebc917f8e664c67952384345.png': '三套配色总览.png',
}
IMAGES = {'.png', '.jpg', '.jpeg', '.webp', '.gif', '.bmp', '.svg'}
ART = IMAGES | {'.ttf', '.otf', '.gdshader', '.mp4', '.aseprite', '.psd', '.blend'}


def natural(value):
    return [int(s) if s.isdigit() else s.casefold() for s in re.split(r'(\d+)', str(value))]


def digest(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def relative(path):
    return path.relative_to(ROOT).as_posix()


def ignored_metadata(path):
    return '__MACOSX' in path.parts or path.name.startswith('._') or path.name in {'.DS_Store', 'Thumbs.db'}


def metadata(path):
    result = {'bytes': path.stat().st_size, 'sha256': digest(path)}
    if path.suffix.lower() in IMAGES - {'.svg'}:
        with Image.open(path) as picture:
            result.update(width=picture.width, height=picture.height, mode=picture.mode)
            picture.verify()
    return result


def copy_checked(source, target, expected):
    target.parent.mkdir(parents=True, exist_ok=True)
    if target.exists():
        if digest(target) != expected:
            raise RuntimeError(f'Refusing to overwrite different content: {target}')
    else:
        shutil.copy2(source, target)
    if digest(target) != expected:
        raise RuntimeError(f'Copy verification failed: {target}')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source-base', type=Path, default=DEFAULT_BASE)
    parser.add_argument('--reference-base', type=Path, default=DEFAULT_REF)
    args = parser.parse_args()
    for pack, _, _ in PACKS:
        if not (args.source_base / pack).is_dir():
            raise FileNotFoundError(args.source_base / pack)
    for name in REFS:
        if not (args.reference_base / name).is_file():
            raise FileNotFoundError(args.reference_base / name)

    # Install exclusions before copying, including when the Godot editor is open.
    for folder in (LIB / '场景/星球核心原始序列', LIB / '开场与演出/开头动画/预览', REPORT):
        folder.mkdir(parents=True, exist_ok=True)
        (folder / '.gdignore').write_text('', encoding='utf-8')

    # Keep an inventory of existing project assets, excluding this delivery library.
    existing = []
    for folder in ('assets', 'fonts', 'shaders', 'docs/references'):
        for path in sorted((ROOT / folder).rglob('*'), key=natural):
            if not path.is_file() or path.is_relative_to(LIB):
                continue
            if path.is_relative_to(ROOT / 'docs/references/technology-colors-2026-10-12'):
                continue
            if path.suffix.lower() in ART:
                existing.append({'path': relative(path), **metadata(path)})
    existing.append({'path': 'icon.svg', **metadata(ROOT / 'icon.svg')})
    by_hash = defaultdict(list)
    for entry in existing:
        by_hash[entry['sha256']].append(entry['path'])

    # Static references are evidence of a file reference, not proof of runtime reachability.
    references = defaultdict(set)
    folders = ('scenes', 'features', 'scripts', 'resources', 'assets', 'fonts', 'shaders', 'tests')
    text_files = [ROOT / 'project.godot']
    for folder in folders:
        text_files += [p for p in (ROOT / folder).rglob('*')
                       if p.is_file() and not p.is_relative_to(LIB)
                       and p.suffix in {'.gd', '.tscn', '.tres', '.gdshader'}]
    for path in text_files:
        content = path.read_text(encoding='utf-8-sig')
        for resource in re.findall(r'res://([^"\n\r]+)', content):
            references[resource].add(relative(path))
    for entry in existing:
        entry['referenced_by'] = sorted(references.get(entry['path'], []))

    files, excluded, packs = [], [], []
    for pack, wrapper, destination in PACKS:
        source_root = args.source_base / pack
        content_root = source_root / wrapper if wrapper else source_root
        members = []
        for source in sorted(source_root.rglob('*'), key=natural):
            if not source.is_file():
                continue
            if ignored_metadata(source):
                excluded.append({'pack': pack, 'source_relative': source.relative_to(source_root).as_posix(),
                                 'reason': 'macOS resource fork / OS metadata; not artwork'})
                continue
            suffix = source.relative_to(content_root) if source.is_relative_to(content_root) else Path('_附带文件') / source.relative_to(source_root)
            target = LIB / destination / suffix
            info = metadata(source)
            copy_checked(source, target, info['sha256'])
            row = {'pack': pack, 'source_relative': source.relative_to(source_root).as_posix(),
                   'path': relative(target), 'category': destination.split('/')[0],
                   'existing_exact_matches': by_hash.get(info['sha256'], []), **info}
            files.append(row)
            members.append(row)
        packs.append({'name': pack, 'source': str(source_root), 'destination': relative(LIB / destination),
                      'files': len(members), 'bytes': sum(x['bytes'] for x in members),
                      'exact_match_files': sum(bool(x['existing_exact_matches']) for x in members)})
        print(f'{pack}: {len(members)} files copied and SHA256 verified', flush=True)

    for source_name, name in REFS.items():
        source = args.reference_base / source_name
        target = ROOT / 'docs/references/technology-colors-2026-10-12' / name
        info = metadata(source)
        copy_checked(source, target, info['sha256'])
        files.append({'pack': '本轮四张参考图', 'source_relative': source_name,
                      'path': relative(target), 'category': '设计参考',
                      'existing_exact_matches': by_hash.get(info['sha256'], []), **info})

    duplicates = defaultdict(list)
    for row in files:
        duplicates[row['sha256']].append(row['path'])
    duplicate_groups = [{'sha256': key, 'paths': value} for key, value in duplicates.items() if len(value) > 1]

    # Group by actual folder and preserve the natural frame sequence, including held frames.
    groups = []
    for scope, rows in (('本次归档', files), ('项目已有', existing)):
        grouped = defaultdict(list)
        for row in rows:
            grouped[str(Path(row['path']).parent).replace('\\', '/')].append(row)
        for folder, members in grouped.items():
            members.sort(key=lambda item: natural(item['path']))
            previews = [r for r in members if Path(r['path']).suffix.lower() in IMAGES]
            groups.append({'scope': scope, 'folder': folder, 'pack': members[0].get('pack', ''),
                           'category': members[0].get('category', '项目已有'),
                           'count': len(members), 'bytes': sum(r['bytes'] for r in members),
                           'preview': previews[0]['path'] if previews else '',
                           'files': [r['path'] for r in members],
                           'sizes': sorted({f"{r['width']} × {r['height']}" for r in members if 'width' in r}),
                           'exact_matches': sorted({p for r in members for p in r.get('existing_exact_matches', [])}),
                           'referenced_by': sorted({p for r in members for p in r.get('referenced_by', [])})})

    summary = {'delivered_files': len(files), 'pack_files': len(files) - len(REFS),
               'reference_images': len(REFS), 'excluded_metadata_files': len(excluded),
               'delivered_bytes': sum(r['bytes'] for r in files), 'existing_art_files': len(existing),
               'files_matching_existing': sum(bool(r['existing_exact_matches']) for r in files),
               'duplicate_groups': len(duplicate_groups), 'unique_delivered_contents': len(duplicates)}
    report = {'generated_at': datetime.now(ZoneInfo('Asia/Shanghai')).isoformat(),
              'summary': summary, 'packs': packs, 'files': files, 'existing_assets': existing,
              'excluded_metadata': excluded, 'duplicate_groups': duplicate_groups, 'groups': groups,
              'notes': [
                  '交付原件逐文件复制并通过 SHA256 核对；未改变像素、命名或动画帧序。相同帧保留，避免改变停顿时长。',
                  '项目已有资源未移动、删除或覆盖；静态路径引用不等于游戏当前运行可达，动态路径也可能漏检。',
                  '没有相同原件不等于尚未接入：项目中可能使用裁切、缩放、图集等派生版本。',
                  '合成 1 是星球核心原始序列（3600帧），现有图集位于 assets/场景动画/星球核心，共46页；对应 provenance.json 记载裁切与压缩流程。',
                  '星球核心原始序列及开头动画/预览含 .gdignore，仅供归档，Godot 不重复导入；其余素材可在 Godot 文件系统中查看。',
                  '开头动画帧率按交付预览说明：p1=4、p2=3、p3=3、p4=4、p5=5、p6=4.5、p7=5；p6 为既有说明中的解释值。其他帧率请查原目录标注或现有场景。',
                  '地鼠花修改版、基础版、高清补充分别保留；未擅自决定替换。科技树三套配色是用户本轮参考，尚未指定唯一配色。',
                  '本目录是文件整理与引用盘点，不是游戏画面截图；本次未做实机视觉验证。音频及 FMOD 银行不属于此美术目录范围。',
              ]}
    REPORT.mkdir(parents=True, exist_ok=True)
    (REPORT / 'inventory.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    template = (ROOT / 'tools/art_inventory_template.html').read_text(encoding='utf-8')
    compact = json.dumps({k: report[k] for k in ('generated_at', 'summary', 'packs', 'groups', 'notes')}, ensure_ascii=False)
    (REPORT / 'index.html').write_text(template.replace('__CATALOG_DATA__', compact.replace('<', '\\u003c')), encoding='utf-8')
    instructions = '\n'.join([
        '美术素材库 · 2026-10-12', '',
        '浏览入口：docs/art_inventory/index.html（从项目根目录打开）',
        '完整来源、SHA256、尺寸、重复组与项目引用：docs/art_inventory/inventory.json', '',
        *report['notes'], '',
        '分类：角色与巢穴 / 场景 / 开场与演出 / 界面。',
        '本轮四张参考图：docs/references/technology-colors-2026-10-12。',
        '本目录保留交付版本；游戏现用资源仍在 assets/物品动画、assets/场景动画、assets/ui 等原路径。',
    ])
    (LIB / '目录说明.txt').write_text(instructions + '\n', encoding='utf-8')
    print(json.dumps(summary, ensure_ascii=False, indent=2), flush=True)


if __name__ == '__main__':
    main()
