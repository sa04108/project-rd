#!/usr/bin/env python3
"""런타임 선택기 없이 독립된 운영·개발 Godot 프로젝트를 준비한다."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import shutil
import sys
import tempfile


STAGES = {
    "production": ("user://", 100, False),
    "development": ("user://development", 10_000_000, True),
}
PROJECT_FILES = ("project.godot", "export_presets.cfg", ".godot-version")
PROJECT_DIRECTORIES = ("game", "data", "assets")
BEGIN = "# STAGE_DEVELOPMENT_BEGIN"
END = "# STAGE_DEVELOPMENT_END"
MANIFEST = ".project-rd-stage.json"
PRODUCER = "project-rd-stage-build-v1"


def preprocess(text: str, stage: str, path: Path) -> str:
    """잘못된 경계는 두 단계 모두 거부하고 개발 코드만 선택적으로 제거한다."""
    result: list[str] = []
    inside = False
    begin_line = 0
    for number, line in enumerate(text.splitlines(keepends=True), 1):
        marker = line.strip()
        if "STAGE_DEVELOPMENT_" in line:
            if marker not in (BEGIN, END):
                raise ValueError(f"{path}:{number}: invalid development marker")
            if marker == BEGIN:
                if inside:
                    raise ValueError(f"{path}:{number}: nested development marker")
                inside = True
                begin_line = number
            else:
                if not inside:
                    raise ValueError(f"{path}:{number}: unmatched development end marker")
                inside = False
            continue
        if not inside or stage == "development":
            result.append(line)
    if inside:
        raise ValueError(f"{path}:{begin_line}: unclosed development marker")
    return "".join(result)


def stage_source(stage: str) -> str:
    directory, diamonds, development = STAGES[stage]
    return (
        "class_name BuildStage\nextends RefCounted\n\n"
        "## 빌드 전처리로 확정된 상수이며 런타임 설정이나 저장에서 읽지 않는다.\n"
        f'const NAME: String = "{stage}"\n'
        f'const SAVE_DIRECTORY: String = "{directory}"\n'
        f"const STARTER_DIAMONDS: int = {diamonds}\n"
        f"const DEVELOPMENT: bool = {str(development).lower()}\n"
    )


def prepare(source: Path, output: Path, stage: str) -> None:
    """입력을 모두 검증한 다음 이전에 생성한 사본만 교체한다."""
    if stage not in STAGES:
        raise ValueError(f"unknown stage: {stage}")
    if output.is_symlink():
        raise ValueError("stage output must not be a symbolic link")
    source = source.resolve(strict=True)
    output = output.resolve()
    if output == source or source.is_relative_to(output):
        raise ValueError("stage output must not replace the source or its ancestors")
    if output.is_relative_to(source) and not output.is_relative_to(source / "artifacts"):
        raise ValueError("stage output inside the source must be under artifacts/")
    if output == source / "artifacts":
        raise ValueError("stage output must not replace the artifacts directory")

    entries: list[Path] = []
    for name in PROJECT_FILES + PROJECT_DIRECTORIES:
        path = source / name
        if not path.exists() or path.is_symlink():
            raise ValueError(f"missing or symbolic-link project input: {path}")
        if name in PROJECT_FILES and not path.is_file():
            raise ValueError(f"project file is not a regular file: {path}")
        if name in PROJECT_DIRECTORIES and not path.is_dir():
            raise ValueError(f"project directory is not a directory: {path}")
        entries.append(path)
        if path.is_dir():
            for child in path.rglob("*"):
                if child.is_symlink() or not (child.is_file() or child.is_dir()):
                    raise ValueError(f"unsupported project input: {child}")

    scripts = {
        path.relative_to(source): preprocess(path.read_text(encoding="utf-8"), stage, path)
        for directory in PROJECT_DIRECTORIES
        for path in (source / directory).rglob("*.gd")
    }
    if Path("game/build_stage.gd") not in scripts:
        raise ValueError("source is missing game/build_stage.gd")

    if output.exists():
        manifest_path = output / MANIFEST
        if not manifest_path.is_file() or manifest_path.is_symlink():
            raise ValueError(f"refusing to replace an unmanaged stage output: {output}")
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        if not isinstance(manifest, dict) or manifest.get("producer") != PRODUCER:
            raise ValueError(f"refusing to replace an unmanaged stage output: {output}")

    output.parent.mkdir(parents=True, exist_ok=True)
    temporary = Path(tempfile.mkdtemp(prefix=f".{output.name}-", dir=output.parent))
    backup: Path | None = None
    try:
        for path in entries:
            destination = temporary / path.name
            if path.is_dir():
                shutil.copytree(path, destination)
            else:
                shutil.copy2(path, destination)
        for relative, text in scripts.items():
            (temporary / relative).write_text(text, encoding="utf-8")
        (temporary / "game/build_stage.gd").write_text(stage_source(stage), encoding="utf-8")
        (temporary / MANIFEST).write_text(
            json.dumps({"producer": PRODUCER, "stage": stage}, indent=2) + "\n",
            encoding="utf-8",
        )
        if output.exists():
            backup = Path(tempfile.mkdtemp(prefix=f".{output.name}-previous-", dir=output.parent))
            backup.rmdir()
            output.rename(backup)
        try:
            temporary.rename(output)
        except OSError:
            if backup is not None:
                backup.rename(output)
                backup = None
            raise
        if backup is not None:
            shutil.rmtree(backup)
    finally:
        if temporary.exists():
            shutil.rmtree(temporary)
    print(f"Prepared {stage} project: {output}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--stage", required=True, choices=tuple(STAGES))
    parser.add_argument("--source", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    try:
        prepare(args.source, args.output, args.stage)
    except (OSError, ValueError) as error:
        print(f"Stage preparation failed: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
