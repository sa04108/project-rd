#!/usr/bin/env python3
"""고정 Web 런타임의 GL 핸들 테이블만 사전으로 바꾸는 빌드 후처리."""

# 상류 코드의 저작권·라이선스 표기와 생성 JS의 나머지 내용은 보존한다.
# Copyright 2010 The Emscripten Authors
# SPDX-License-Identifier: MIT
# https://github.com/emscripten-core/emscripten/blob/4.0.20/LICENSE
# https://github.com/emscripten-core/emscripten/issues/21921

import argparse
import hashlib
import os
from pathlib import Path
import stat
import sys
import tempfile
import zipfile


ROOT = Path(__file__).resolve().parent.parent
PIN = "4.7.2-stable"
# 공식 단일 스레드·확장 미사용 템플릿과 별도로 검토한 변환 결과만 허용한다.
VARIANTS = {
    "release": {
        "template": "d3ee2f08cef0cf3cf6678a6355a92a8db48ccdd35cbd2e8bfd5f0e8a0b4032a0",
        "original": "33c94cb3175f3333b82e2a3be5e8e86f77986f0aa2042b1631f6367a4e5bb6ba",
        "patched": "c41f08d87b6d900c40a5c1c337612620459cdef5fa69c80cb5d4c596df382a12",
    },
    "debug": {
        "template": "08962aefef811b603541d7951ac67ef00413aad2d978855183c28adee98f626a",
        "original": "ffc3898b59fba6f5af0c02f76e5ee526cc061e65c7d2d6f4f98186876cea15c4",
        "patched": "99fb3102fb48b0cd1b1faba416f20961684e8a1a63b38d748d66e773bb04d5ba",
    },
}
TABLES = (
    "buffers", "programs", "framebuffers", "renderbuffers", "textures", "shaders",
    "vaos", "contexts", "queries", "samplers", "transformFeedbacks", "syncs",
)
RETIRED_TABLES = (
    "buffers", "framebuffers", "programs", "queries", "renderbuffers", "shaders",
    "syncs", "textures", "vaos", "contexts",
)


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def validate_template(path: Path, variant: dict[str, str]) -> None:
    if sha256(path.read_bytes()) != variant["template"]:
        raise ValueError("Unknown Web template hash; review the pinned variant before exporting")
    with zipfile.ZipFile(path) as archive:
        if sha256(archive.read("godot.js")) != variant["original"]:
            raise ValueError("Web template runtime does not match the reviewed variant")


def patch_runtime(original: bytes, variant: dict[str, str]) -> bytes:
    digest = sha256(original)
    if digest == variant["patched"]:
        return original
    if digest != variant["original"]:
        raise ValueError("Unknown generated JS hash; no changes made, renewed review required")

    text = original.decode("utf-8")

    def replace_once(before: str, after: str) -> None:
        nonlocal text
        if text.count(before) != 1:
            raise ValueError("Missing or ambiguous WebGL patch anchor: " + before)
        text = text.replace(before, after, 1)

    # 검토한 두 런타임의 70개 참조는 숫자 키 접근 또는 아래 두 함수의 인수다.
    # 배열 길이를 쓰는 유일한 테이블 소비자는 getNewId의 빈칸 채우기 루프다.
    for name in TABLES:
        replace_once(
            f",{name}:[],",
            f",{name}:Object.assign(Object.create(null),{{0:null}}),",
        )
    replace_once(
        "getNewId:table=>{var ret=GL.counter++;for(var i=table.length;i<ret;i++){table[i]=null}return ret}",
        "getNewId:table=>GL.counter++",
    )
    # 전역 ID 순서와 0=null을 보존하며, 해제된 항목만 제거한다. ID를 재사용하지 않는다.
    for name in RETIRED_TABLES:
        index = "contextHandle" if name == "contexts" else "id"
        replace_once(f"GL.{name}[{index}]=null", f"if({index})delete GL.{name}[{index}]")

    patched = text.encode("utf-8")
    if sha256(patched) != variant["patched"]:
        raise ValueError("Patched JS hash differs from the reviewed result; no changes made")
    return patched


def atomic_replace(path: Path, original: bytes, patched: bytes) -> None:
    # 같은 디렉터리의 임시 파일로 완성한 뒤 교체해 중간 산출물 노출을 막는다.
    original_stat = path.stat()
    temporary: Path | None = None
    try:
        with tempfile.NamedTemporaryFile(dir=path.parent, prefix=f".{path.name}.", suffix=".tmp", delete=False) as stream:
            temporary = Path(stream.name)
            stream.write(patched)
            stream.flush()
            os.fsync(stream.fileno())
        os.chmod(temporary, stat.S_IMODE(original_stat.st_mode))
        if path.is_symlink() or path.read_bytes() != original:
            raise ValueError("Runtime changed during postprocess; refusing to overwrite it")
        os.replace(temporary, path)
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("runtime", type=Path, help="내보낸 index.js 경로")
    parser.add_argument("--mode", choices=VARIANTS, required=True)
    parser.add_argument("--template", type=Path, required=True, help="내보내기에 사용한 공식 Web template zip")
    args = parser.parse_args()
    try:
        if (ROOT / ".godot-version").read_text().strip() != PIN:
            raise ValueError("Unsupported Godot pin; this postprocess requires " + PIN)
        if args.runtime.is_symlink() or not args.runtime.is_file():
            raise ValueError("Runtime must be a regular, non-symlink JS file")
        variant = VARIANTS[args.mode]
        validate_template(args.template, variant)
        original = args.runtime.read_bytes()
        patched = patch_runtime(original, variant)
        if patched == original:
            print(f"WebGL tables already patched ({args.mode}): {args.runtime}")
        else:
            atomic_replace(args.runtime, original, patched)
            print(f"WebGL tables patched ({args.mode}): {args.runtime}")
        return 0
    except (OSError, ValueError, KeyError, zipfile.BadZipFile) as error:
        print(f"Web runtime postprocess failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
