#!/usr/bin/env python3
"""게임 카탈로그에서 아트 계획과 실제 생성 범위를 기록한다."""

from __future__ import annotations

import json
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
UNIT_FILE = ROOT / "data" / "units.json"
ENEMY_FILE = ROOT / "data" / "enemies.json"
OUTPUT_FILE = ROOT / "assets" / "art" / "manifest.json"
EXPECTED = {"units": 34, "normal": 40, "boss": 10, "special": 3}
FAMILIES = {"humanoid", "heavy", "quadruped", "multi", "floating", "blob", "dragon"}


def _read(path: Path) -> list[dict]:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, list):
        raise ValueError(f"{path.relative_to(ROOT)} must contain a JSON array")
    return value


def _category_for_enemy(enemy: dict) -> str:
    kind = str(enemy.get("kind", ""))
    if kind in ("boss", "final"):
        return "boss"
    return kind


def _record(entry: dict, category: str, family_resources: dict[str, dict]) -> dict:
    entity_id = str(entry["id"])
    family = str(entry["family"])
    resource = family_resources[family]
    planned_identity = {"name": str(entry["name"]), "family": family, "color": str(entry["color"])}
    if category == "units":
        planned_identity["role"] = str(entry.get("role", ""))
        planned_identity["description"] = str(entry.get("description", ""))
    else:
        planned_identity["kind"] = str(entry.get("kind", ""))
    portrait_path = f"assets/art/portraits/{entity_id}.png"
    portrait_status = "generated_unreviewed" if (ROOT / portrait_path).is_file() else "pending_generation"
    return {
        "id": entity_id,
        "category": category,
        "planned_identity": planned_identity,
        "realized_visual": {
            "status": resource["status"],
            "shared_family_resource": family,
            "atlas": resource["atlas"],
            "frame_layout": resource["frame_layout"],
            "palette_tint": planned_identity["color"],
        },
        "portrait_resource": {
            "status": portrait_status,
            "path": portrait_path,
            "distinct_per_catalog_entry": True,
        },
    }


def build_manifest() -> dict:
    units = _read(UNIT_FILE)
    enemies = _read(ENEMY_FILE)
    families = {str(entry["family"]) for entry in units + enemies}
    unknown = families - FAMILIES
    missing = FAMILIES - families
    if unknown or missing:
        raise ValueError(f"family mismatch: unknown={sorted(unknown)}, missing={sorted(missing)}")

    family_resources: dict[str, dict] = {}
    for family in sorted(FAMILIES):
        base = f"assets/art/families/{family}"
        atlas = f"{base}/sprite-sheet-alpha.png"
        frame_layout = f"{base}/manifest.json"
        atlas_path = ROOT / atlas
        manifest_path = ROOT / frame_layout
        if atlas_path.is_file() and manifest_path.is_file():
            status = "generated_unreviewed"
            inspect_path = ROOT / base / "sprite-inspect.report.json"
            score_path = ROOT / base / "sprite-score.report.json"
            if inspect_path.is_file() and score_path.is_file():
                try:
                    inspect = json.loads(inspect_path.read_text(encoding="utf-8"))
                    score = json.loads(score_path.read_text(encoding="utf-8"))
                    if inspect.get("ok") is True and score.get("ok") is True:
                        status = "auto_checks_passed"
                except (OSError, json.JSONDecodeError):
                    pass
        else:
            status = "pending_generation"
        review = {"status": "pending"}
        receipt_path = ROOT / base / "pipeline-receipt.json"
        if receipt_path.is_file():
            review = json.loads(receipt_path.read_text(encoding="utf-8")).get("human_visual_review", review)
        if not isinstance(review, dict):
            review = {"status": str(review)}
        family_resources[family] = {
            "status": status,
            "human_visual_review": review,
            "pipeline": "sprite-gen",
            "run_dir": f"{base}/sprite_run",
            "source_image": f"{base}/source.png",
            "atlas": atlas,
            "frame_layout": frame_layout,
            "states": {
                "idle": {"frames": 6, "fps": 6, "loop": True},
                "walk": {"frames": 6, "fps": 8, "loop": True, "qa": "experimental_until_motion_pass"},
                "attack": {"frames": 6, "fps": 8, "loop": False},
            },
        }

    records = [_record(entry, "units", family_resources) for entry in units]
    records.extend(_record(entry, _category_for_enemy(entry), family_resources) for entry in enemies)

    counts = {
        "units": sum(record["category"] == "units" for record in records),
        "normal": sum(record["category"] == "normal" for record in records),
        "boss": sum(record["category"] == "boss" for record in records),
        "special": sum(record["category"] == "special" for record in records),
    }
    if counts != EXPECTED:
        raise ValueError(f"catalog coverage mismatch: expected {EXPECTED}, found {counts}")
    ids = [record["id"] for record in records]
    if len(ids) != len(set(ids)):
        raise ValueError("catalog entity IDs must be globally unique")
    generated_statuses = ("generated_unreviewed", "auto_checks_passed", "manually_reviewed")
    generated_families = sum(value["status"] in generated_statuses for value in family_resources.values())
    auto_checked_families = sum(value["status"] in ("auto_checks_passed", "manually_reviewed") for value in family_resources.values())
    manually_reviewed_families = sum(value["human_visual_review"].get("status") in ("reviewed", "reviewed_with_notes") for value in family_resources.values())
    generated_entries = sum(family_resources[record["planned_identity"]["family"]]["status"] in generated_statuses for record in records)
    auto_checked_entries = sum(family_resources[record["planned_identity"]["family"]]["status"] in ("auto_checks_passed", "manually_reviewed") for record in records)
    manually_reviewed_entries = sum(family_resources[record["planned_identity"]["family"]]["human_visual_review"].get("status") in ("reviewed", "reviewed_with_notes") for record in records)

    environment_resources = {}
    for name, path in (
        ("menu_background", "assets/art/backgrounds/guild.png"),
        ("battle_background", "assets/art/backgrounds/battlefield.png"),
    ):
        environment_resources[name] = {
            "status": "generated_unreviewed" if (ROOT / path).is_file() else "pending_generation",
            "path": path,
        }

    return {
        "schema": 1,
        "generator": "sprite-gen",
        "coverage": {
            "planned_catalog_entries": counts,
            "planned_entry_total": len(records),
            "generated_family_atlases": generated_families,
            "auto_checks_passed_family_atlases": auto_checked_families,
            "manually_reviewed_family_atlases": manually_reviewed_families,
            "catalog_entries_with_generated_atlas": generated_entries,
            "catalog_entries_with_auto_checks_passed_atlas": auto_checked_entries,
            "catalog_entries_with_manually_reviewed_atlas": manually_reviewed_entries,
        },
        "image_model_tier": {
            "status": "unverified",
            "identifier": None,
            "reason": "conversation image_gen does not expose a selectable or reported model identifier",
        },
        "family_resources": family_resources,
        "environment_resources": environment_resources,
        "identity_policy": "distinct portraits cover 87 catalog entries; allies use individual art with whole-texture motion, enemies share seven animated family atlases with tint; tint is not unique art",
        "portrait_coverage": {
            "planned_distinct_catalog_portraits": len(records),
            "present_distinct_catalog_portraits": sum(record["portrait_resource"]["status"] != "pending_generation" for record in records),
        },
        "entries": sorted(records, key=lambda item: item["id"]),
    }


def main() -> int:
    try:
        manifest = build_manifest()
        OUTPUT_FILE.parent.mkdir(parents=True, exist_ok=True)
        OUTPUT_FILE.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    except (OSError, ValueError, KeyError, json.JSONDecodeError) as error:
        print(f"art manifest: {error}", file=sys.stderr)
        return 1
    print(f"wrote {OUTPUT_FILE.relative_to(ROOT)} for {len(manifest['entries'])} unique catalog IDs")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
