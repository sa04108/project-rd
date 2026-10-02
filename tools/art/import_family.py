#!/usr/bin/env python3
"""검증된 sprite-gen 아틀라스를 게임 리소스 경로로 가져온다."""

from __future__ import annotations

import argparse
import json
import shutil
import struct
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
FAMILIES = {"humanoid", "heavy", "quadruped", "multi", "floating", "blob", "dragon"}
REQUIRED_STATES = {"idle", "walk", "attack"}


def png_info(path: Path) -> tuple[int, int, int]:
    with path.open("rb") as image:
        header = image.read(26)
    if len(header) < 26 or header[:8] != b"\x89PNG\r\n\x1a\n" or header[12:16] != b"IHDR":
        raise ValueError(f"{path} is not a valid PNG")
    width, height = struct.unpack(">II", header[16:24])
    return width, height, header[25]


def import_family(family: str, allow_unreviewed: bool) -> None:
    if family not in FAMILIES:
        raise ValueError(f"unknown family: {family}")
    target = ROOT / "assets" / "art" / "families" / family
    run_dir = target / "sprite_run"
    layout_path = run_dir / "manifest.json"
    atlas_source = run_dir / "sprite-sheet-alpha.png"
    inspect_source = run_dir / "sprite-inspect.report.json"
    score_source = run_dir / "sprite-score.report.json"
    for path in (layout_path, atlas_source, inspect_source, score_source):
        if not path.is_file():
            raise ValueError(f"required sprite-gen output missing: {path.relative_to(ROOT)}")

    layout = json.loads(layout_path.read_text(encoding="utf-8"))
    frame_layout = layout.get("frame_layout", {})
    animation = layout.get("animation", {}).get("rows", {})
    if (layout.get("cell", {}).get("width"), layout.get("cell", {}).get("height")) != (256, 256):
        raise ValueError("runtime frames must use 256x256 cells")
    rows = frame_layout.get("rows", {})
    if not REQUIRED_STATES.issubset(rows) or not REQUIRED_STATES.issubset(animation):
        raise ValueError(f"runtime manifest must include {sorted(REQUIRED_STATES)}")
    sheet_width = int(frame_layout.get("sheetWidth", 0))
    sheet_height = int(frame_layout.get("sheetHeight", 0))
    width, height, color_type = png_info(atlas_source)
    if (width, height) != (sheet_width, sheet_height) or color_type != 6:
        raise ValueError("atlas must be a matching RGBA PNG")
    for state in REQUIRED_STATES:
        cells = rows[state]
        meta = animation[state]
        if len(cells) != 6 or int(meta.get("frames", len(cells))) != 6:
            raise ValueError(f"{state} must have six frames")
        if int(meta.get("cellWidth", 256)) != 256 or int(meta.get("cellHeight", 256)) != 256:
            raise ValueError(f"{state} frame dimensions must be 256x256")
        if int(meta.get("fps", 0)) <= 0 or not isinstance(meta.get("loop"), bool):
            raise ValueError(f"{state} animation timing is incomplete")
        durations = meta.get("durations_ms", [])
        if durations and (len(durations) != len(cells) or any(int(value) <= 0 for value in durations)):
            raise ValueError(f"{state} has invalid frame durations")
        for cell in cells:
            x, y, w, h = (int(cell[key]) for key in ("x", "y", "w", "h"))
            if w != 256 or h != 256 or x < 0 or y < 0 or x + w > width or y + h > height:
                raise ValueError(f"{state} contains an out-of-bounds frame")

    inspect = json.loads(inspect_source.read_text(encoding="utf-8"))
    score = json.loads(score_source.read_text(encoding="utf-8"))
    checks_passed = inspect.get("ok") is True and score.get("ok") is True
    if not checks_passed and not allow_unreviewed:
        raise ValueError("sprite-gen inspect/score did not both pass; use --allow-unreviewed to import with an explicit status")

    shutil.copy2(atlas_source, target / "sprite-sheet-alpha.png")
    shutil.copy2(layout_path, target / "manifest.json")
    shutil.copy2(inspect_source, target / "sprite-inspect.report.json")
    shutil.copy2(score_source, target / "sprite-score.report.json")
    receipt = {
        "pipeline": "aldegad/sprite-gen",
        "stages": ["prepare", "prompted_image_generation", "extract", "compose-atlas", "inspect", "score"],
        "generation_route": "conversation image_gen tool using sprite-gen row prompts and layout guides",
        "image_model_identifier": None,
        "highest_tier_verified": False,
        "sprite_gen_checks_passed": checks_passed,
        "human_visual_review": {"status": "pending"},
    }
    (target / "pipeline-receipt.json").write_text(json.dumps(receipt, indent=2) + "\n", encoding="utf-8")
    print(f"imported {family}: {width}x{height} RGBA atlas; sprite-gen checks {'passed' if checks_passed else 'pending'}; human review pending")


def main() -> int:
    parser = argparse.ArgumentParser(description="Import one sprite-gen family atlas into the runtime resource path.")
    parser.add_argument("family", choices=sorted(FAMILIES))
    parser.add_argument("--allow-unreviewed", action="store_true", help="import valid output even when sprite-gen automatic checks did not pass")
    args = parser.parse_args()
    try:
        import_family(args.family, args.allow_unreviewed)
    except (OSError, ValueError, KeyError, TypeError, json.JSONDecodeError) as error:
        print(f"art import: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
