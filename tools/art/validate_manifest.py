#!/usr/bin/env python3
"""아트 계획 매니페스트와 카탈로그 및 실제 파일의 일관성을 검사한다."""

from __future__ import annotations

import json
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
MANIFEST = ROOT / "assets" / "art" / "manifest.json"
COUNTS = {"units": 34, "normal": 40, "boss": 10, "special": 3}
FAMILIES = {"humanoid", "heavy", "quadruped", "multi", "floating", "blob", "dragon"}


def read_json(path: Path):
    return json.loads(path.read_text(encoding="utf-8"))


def validate() -> list[str]:
    errors: list[str] = []
    data = read_json(MANIFEST)
    units = read_json(ROOT / "data" / "units.json")
    enemies = read_json(ROOT / "data" / "enemies.json")
    expected = {str(item["id"]): "units" for item in units}
    for enemy in enemies:
        kind = str(enemy.get("kind", ""))
        expected[str(enemy["id"])] = "boss" if kind in ("boss", "final") else kind
    if len(expected) != len(units) + len(enemies):
        errors.append("source catalogs contain duplicate global IDs")
    manifest_entries = data.get("entries", [])
    found = {str(entry.get("id")): entry for entry in manifest_entries}
    if len(found) != len(manifest_entries):
        errors.append("manifest contains duplicate IDs")
    if set(found) != set(expected):
        errors.append("manifest entry IDs do not match catalog IDs")
    counts = {category: 0 for category in COUNTS}
    for identity, category in expected.items():
        if identity not in found:
            continue
        entry = found[identity]
        if entry.get("category") != category:
            errors.append(f"{identity} has category {entry.get('category')!r}, expected {category!r}")
        counts[category] += 1
    if counts != COUNTS:
        errors.append(f"catalog counts differ: {counts}")

    resources = data.get("family_resources", {})
    if set(resources) != FAMILIES:
        errors.append("family resource keys do not match the seven required families")
    valid_statuses = {"pending_generation", "generated_unreviewed", "auto_checks_passed", "manually_reviewed"}
    for family, resource in resources.items():
        status = resource.get("status")
        if status not in valid_statuses:
            errors.append(f"{family} has unknown status {status!r}")
        atlas = ROOT / str(resource.get("atlas", ""))
        layout = ROOT / str(resource.get("frame_layout", ""))
        present = atlas.is_file() and layout.is_file()
        if status == "pending_generation" and present:
            errors.append(f"{family} has atlas files but is marked pending")
        if status != "pending_generation" and not present:
            errors.append(f"{family} is marked realized but atlas/layout is missing")
        if present:
            try:
                layout_data = read_json(layout)
                rows = layout_data.get("frame_layout", {}).get("rows", {})
                animation = layout_data.get("animation", {}).get("rows", {})
                if (layout_data.get("cell", {}).get("width"), layout_data.get("cell", {}).get("height")) != (256, 256):
                    errors.append(f"{family} does not use 256x256 frame cells")
                for state, state_data in resource.get("states", {}).items():
                    if state not in rows or state not in animation:
                        errors.append(f"{family} missing runtime row {state}")
                        continue
                    cells = rows[state]
                    frame_count = int(state_data.get("frames", 0))
                    if len(cells) != frame_count:
                        errors.append(f"{family}/{state} frame count differs from planned {frame_count}")
                    meta = animation[state]
                    if int(meta.get("fps", 0)) != int(state_data.get("fps", 0)) or bool(meta.get("loop")) != bool(state_data.get("loop")):
                        errors.append(f"{family}/{state} animation timing differs from plan")
            except (OSError, ValueError, TypeError, json.JSONDecodeError) as error:
                errors.append(f"{family} layout could not be read: {error}")

    for entry in manifest_entries:
        identity = str(entry.get("id", ""))
        visual = entry.get("realized_visual", {})
        family = str(entry.get("planned_identity", {}).get("family", ""))
        if family not in resources:
            errors.append(f"{entry.get('id')} references unknown family {family!r}")
            continue
        resource = resources[family]
        for key in ("atlas", "frame_layout", "shared_family_resource"):
            expected_value = family if key == "shared_family_resource" else resource.get(key)
            if visual.get(key) != expected_value:
                errors.append(f"{entry.get('id')} has inconsistent realized_visual.{key}")
        if visual.get("status") != resource.get("status"):
            errors.append(f"{entry.get('id')} status differs from its shared family resource")
        portrait = entry.get("portrait_resource", {})
        portrait_path = str(portrait.get("path", ""))
        if portrait_path != f"assets/art/portraits/{identity}.png" or portrait.get("distinct_per_catalog_entry") is not True:
            errors.append(f"{identity} does not declare its individual portrait resource")
        if portrait.get("status") == "pending_generation" and (ROOT / portrait_path).is_file():
            errors.append(f"{identity} portrait exists but is marked pending")
        if portrait.get("status") != "pending_generation" and not (ROOT / portrait_path).is_file():
            errors.append(f"{identity} portrait is marked realized but missing")

    portrait_coverage = data.get("portrait_coverage", {})
    actual_portraits = sum((ROOT / f"assets/art/portraits/{identity}.png").is_file() for identity in expected)
    if portrait_coverage.get("planned_distinct_catalog_portraits") != len(expected):
        errors.append("portrait plan does not cover every catalog entry")
    if portrait_coverage.get("present_distinct_catalog_portraits") != actual_portraits:
        errors.append("portrait coverage does not match files present on disk")

    for name, resource in data.get("environment_resources", {}).items():
        path = ROOT / str(resource.get("path", ""))
        if resource.get("status") == "pending_generation" and path.is_file():
            errors.append(f"{name} exists but is marked pending")
        if resource.get("status") != "pending_generation" and not path.is_file():
            errors.append(f"{name} is marked realized but missing: {path}")
    return errors


def main() -> int:
    try:
        errors = validate()
    except (OSError, ValueError, KeyError, TypeError, json.JSONDecodeError) as error:
        print(f"art manifest validation: {error}", file=sys.stderr)
        return 1
    if errors:
        for error in errors:
            print(f"art manifest validation: {error}", file=sys.stderr)
        return 1
    print("art manifest is consistent with catalogs, runtime rows, and installed files")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
