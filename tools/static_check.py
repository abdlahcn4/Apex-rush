#!/usr/bin/env python3
"""Static verification for APEX RUSH.

No engine, no GPU, no gameplay: this walks the project files and proves that every
resource the scripts ask for exists, that the class/function contracts line up, and that
the export configuration is coherent. Exit code 1 on any failure.
"""
from __future__ import annotations

import json
import os
import re
import struct
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GODOT = os.path.join(ROOT, "godot")
SCRIPTS = os.path.join(GODOT, "scripts")

errors: list[str] = []
warnings: list[str] = []
notes: list[str] = []


def read(path: str) -> str:
    with open(path, "r", encoding="utf-8") as fh:
        return fh.read()


def gd_files() -> list[str]:
    return sorted(
        os.path.join(SCRIPTS, f)
        for f in os.listdir(SCRIPTS)
        if f.endswith(".gd")
    )


def res_to_path(res: str) -> str:
    return os.path.join(GODOT, res[len("res://"):])


# --------------------------------------------------------------------------- #
# 1. resource literals
# --------------------------------------------------------------------------- #
RES_RE = re.compile(r'"(res://[^"]+)"')
used: dict[str, list[str]] = {}
for path in gd_files():
    src = read(path)
    for m in RES_RE.finditer(src):
        ref = m.group(1)
        if ref.endswith("/") or "%" in ref:
            continue
        used.setdefault(ref, []).append(os.path.basename(path))

for ref, where in sorted(used.items()):
    if not os.path.exists(res_to_path(ref)):
        errors.append(f"missing resource {ref} (referenced by {', '.join(sorted(set(where)))})")
notes.append(f"resource literals checked: {len(used)}")

# --------------------------------------------------------------------------- #
# 2. data-driven asset names (audio map, sky names, vegetation, buildings)
# --------------------------------------------------------------------------- #
lib = read(os.path.join(SCRIPTS, "asset_library.gd"))
audio_block = re.search(r"const AUDIO := \{(.*?)\n\}", lib, re.S)
audio_files: dict[str, str] = {}
if audio_block:
    for key, val in re.findall(r'"([^"]+)":\s*"([^"]+)"', audio_block.group(1)):
        audio_files[key] = val
        full = os.path.join(GODOT, "assets", "audio", val)
        if not os.path.exists(full) or os.path.getsize(full) == 0:
            errors.append(f"AUDIO['{key}'] -> missing/empty {val}")
notes.append(f"audio entries: {len(audio_files)} ({sum(os.path.getsize(os.path.join(GODOT,'assets','audio',v)) for v in audio_files.values())//1024} KB)")

maps_doc = json.load(open(os.path.join(GODOT, "data", "maps.json"), encoding="utf-8"))
maps = maps_doc["maps"] if isinstance(maps_doc, dict) else maps_doc
sky_dir = os.path.join(GODOT, "assets", "environment", "sky")
for m in maps:
    theme = m.get("theme", {})
    hdri = theme.get("sky_hdri", "")
    if hdri:
        p = os.path.join(sky_dir, hdri + ".hdr")
        if not os.path.exists(p):
            errors.append(f"map {m['id']}: sky_hdri missing {hdri}.hdr")
notes.append(f"maps: {len(maps)} — " + ", ".join(
    f"{m['id']}[sky={m.get('theme',{}).get('sky_hdri','-')},veg={m.get('theme',{}).get('veg','-')},city={m.get('theme',{}).get('city','-')},road={m.get('theme',{}).get('road_kind','-')}]"
    for m in maps))

game = read(os.path.join(SCRIPTS, "game.gd"))
veg_dir = os.path.join(GODOT, "assets", "environment", "vegetation")
veg_presets = re.search(r"const VEG_PRESETS := \{(.*?)\n\}", game, re.S)
veg_models = set()
if veg_presets:
    veg_models = set(re.findall(r'\["([A-Za-z_]+)",', veg_presets.group(1)))
for name in sorted(veg_models):
    if not os.path.exists(os.path.join(veg_dir, name + ".glb")):
        errors.append(f"vegetation model missing: {name}.glb")
notes.append(f"vegetation models: {len(veg_models)} — {', '.join(sorted(veg_models))}")

bld_dir = os.path.join(GODOT, "assets", "environment", "buildings")
city_dir = os.path.join(GODOT, "assets", "kenney_city_kit")
for const_name, directory in (("CITY_MODELS", bld_dir), ("CITY_KIT", city_dir)):
    block = re.search(rf"const {const_name} := \[(.*?)\]", game, re.S)
    if not block:
        errors.append(f"game.gd: {const_name} not found")
        continue
    for name in re.findall(r'"([^"]+)"', block.group(1)):
        if not os.path.exists(os.path.join(directory, name + ".glb")):
            errors.append(f"{const_name}: missing {name}.glb in {os.path.basename(directory)}")
notes.append("building models verified against their directories")

# --------------------------------------------------------------------------- #
# 3. imported 3D assets: GLB header + payload sanity
# --------------------------------------------------------------------------- #
def glb_report(path: str) -> tuple[int, int]:
    with open(path, "rb") as fh:
        head = fh.read(12)
        magic, _version, length = struct.unpack("<III", head)
        if magic != 0x46546C67:
            raise ValueError("not a GLB")
        chunk_len, chunk_type = struct.unpack("<II", fh.read(8))
        body = fh.read(chunk_len)
    doc = json.loads(body.decode("utf-8"))
    return len(doc.get("meshes", [])), len(doc.get("materials", []))


glbs = []
for base, _dirs, files in os.walk(os.path.join(GODOT, "assets")):
    for f in files:
        if f.endswith(".glb"):
            glbs.append(os.path.join(base, f))
mesh_total = 0
for path in sorted(glbs):
    try:
        meshes, mats = glb_report(path)
        mesh_total += meshes
    except Exception as exc:  # noqa: BLE001
        errors.append(f"corrupt GLB {os.path.relpath(path, GODOT)}: {exc}")
notes.append(f"GLB files: {len(glbs)} ({mesh_total} meshes total)")

hdrs = [f for f in os.listdir(sky_dir) if f.endswith(".hdr")]
for f in hdrs:
    size = os.path.getsize(os.path.join(sky_dir, f))
    if size < 100_000:
        warnings.append(f"{f} is only {size} B — suspiciously small for an HDRI")
notes.append(f"HDRIs: {len(hdrs)} — {', '.join(sorted(hdrs))}")

# --------------------------------------------------------------------------- #
# 4. GDScript compile-error guards (these are the ones the parser check misses)
# --------------------------------------------------------------------------- #
for path in gd_files():
    src = read(path)
    declared: dict[str, int] = {}
    for line_no, line in enumerate(src.splitlines(), 1):
        m = re.match(r"^(?:const|var)\s+([A-Za-z_]\w*)\s*:", line)
        if not m:
            continue
        name = m.group(1)
        if name in declared:
            errors.append(
                f"{os.path.basename(path)}:{line_no}: duplicate top-level '{name}' "
                f"(first declared on line {declared[name]})"
            )
        declared[name] = line_no
    funcs: dict[str, int] = {}
    for line_no, line in enumerate(src.splitlines(), 1):
        m = re.match(r"^(?:static )?func (\w+)\(", line)
        if not m:
            continue
        if m.group(1) in funcs:
            errors.append(
                f"{os.path.basename(path)}:{line_no}: duplicate function '{m.group(1)}' "
                f"(first defined on line {funcs[m.group(1)]})"
            )
        funcs[m.group(1)] = line_no
    # a loop variable over an untyped Array is a Variant: inferring from its members fails
    loop_vars = set()
    for line in src.splitlines():
        m = re.match(r"^\s*for (\w+) in ", line)
        if m:
            loop_vars.add(m.group(1))
    for line_no, line in enumerate(src.splitlines(), 1):
        m = re.match(r"^\s*var (\w+) :?= *([\w.]+)", line)
        if m and ":=" in line and m.group(2).split(".")[0] in loop_vars and " as " not in line:
            warnings.append(
                f"{os.path.basename(path)}:{line_no}: ':=' from loop variable "
                f"'{m.group(2)}' — declare the type explicitly"
            )
    # ':=' infers a type; inferring from a Variant is a compile error in GDScript 4
    for line_no, line in enumerate(src.splitlines(), 1):
        if " as " in line:
            continue  # an explicit cast gives the type
        if re.search(r":=\s*\w+\[", line) or re.search(r":=\s*\w+\.get\(", line):
            warnings.append(f"{os.path.basename(path)}:{line_no}: ':=' from an untyped value")

# --------------------------------------------------------------------------- #
# 5. GDScript contracts
# --------------------------------------------------------------------------- #
classes: dict[str, str] = {}
for path in gd_files():
    m = re.search(r"^class_name\s+(\w+)", read(path), re.M)
    if m:
        if m.group(1) in classes:
            errors.append(f"duplicate class_name {m.group(1)} in {os.path.basename(path)} and {os.path.basename(classes[m.group(1)])}")
        classes[m.group(1)] = path
notes.append(f"classes: {len(classes)} — {', '.join(sorted(classes))}")

static_funcs: dict[str, set[str]] = {}
for name, path in classes.items():
    src = read(path)
    static_funcs[name] = set(re.findall(r"^static func (\w+)", src, re.M))
    static_funcs[name] |= set(re.findall(r"^func (\w+)", src, re.M))

call_re = re.compile(r"\b(CarHero|CarBuilder|AssetLibrary)\.(\w+)\(")
for path in gd_files():
    for cls, fn in call_re.findall(read(path)):
        if cls in static_funcs and fn not in static_funcs[cls]:
            errors.append(f"{os.path.basename(path)}: {cls}.{fn}() does not exist")

# the old procedural car must only run as a fallback
builder = read(os.path.join(SCRIPTS, "car_builder.gd"))
if "CarHero.available()" not in builder:
    errors.append("car_builder.gd does not route through CarHero")
notes.append("vehicle path: CarHero (Khronos CC-BY car) with procedural fallback")

# keys the vehicle reads out of the model dictionary must all be produced
hero = read(os.path.join(SCRIPTS, "car_hero.gd"))
vehicle = read(os.path.join(SCRIPTS, "vehicle.gd"))
for key in sorted(set(re.findall(r"model\.([a-z_]+)", vehicle))):
    if key in {"get", "has", "name", "find_child", "find_children"}:
        continue
    if f'"{key}"' not in hero:
        errors.append(f"vehicle.gd reads model.{key} but CarHero does not set it")

# --------------------------------------------------------------------------- #
# 6. project + export configuration
# --------------------------------------------------------------------------- #
cfg_text = read(os.path.join(GODOT, "project.godot"))
for scene in re.findall(r'run/main_scene="res://([^"]+)"', cfg_text):
    if not os.path.exists(os.path.join(GODOT, scene)):
        errors.append(f"main_scene missing: {scene}")
main_scene = re.search(r'run/main_scene="res://([^"]+)"', cfg_text)
if main_scene:
    scene_path = os.path.join(GODOT, main_scene.group(1))
    if scene_path.endswith(".tscn"):
        scene_text = read(scene_path)
        for script in re.findall(r'path="res://([^"]+\.gd)"', scene_text):
            if not os.path.exists(os.path.join(GODOT, script)):
                errors.append(f"{main_scene.group(1)} references missing script {script}")

presets = read(os.path.join(GODOT, "export_presets.cfg"))
for required in ("Android", "Windows Desktop"):
    if f'name="{required}"' not in presets:
        errors.append(f"export_presets.cfg missing {required} preset")
notes.append("export presets: " + ", ".join(re.findall(r'name="([^"]+)"', presets.split("platform=")[0] if False else presets)[:6]))

# --- report ---------------------------------------------------------------- #
print("APEX RUSH — static verification\n")
for n in notes:
    print(f"  · {n}")
if warnings:
    print("\nwarnings:")
    for w in warnings:
        print(f"  ! {w}")
if errors:
    print("\nFAILURES:")
    for e in errors:
        print(f"  x {e}")
    print(f"\n{len(errors)} failure(s)")
    sys.exit(1)
print("\nOK — every referenced resource exists, contracts line up, exports configured")
