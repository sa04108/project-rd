#!/usr/bin/env python3
"""검토한 고정 Web shell에 페이지 수명 저장 잠금을 원자적으로 추가한다."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import stat
import tempfile


ROOT = Path(__file__).resolve().parent.parent
SCRIPT_NAME = "web-session-lock.js"
SCRIPT_TAG = f'\t\t<script src="{SCRIPT_NAME}"></script>\n'
ENGINE_TAG = '\t\t<script src="index.js"></script>\n'
INLINE_SHA256 = "4263a81bc28cce875aa848bd90ec14101a201bdca0f80d42cfc59e73a6145e73"
PATHS = (
    ["/userfs"],
    ["/userfs/godot/app_userdata/project-rd · 용병 길드/development"],
)
START = "\t\tengine.startGame({"
END = "\t\t}, displayFailureNotice);"
PATCHED_START = """\t\trdStartWithSessionLock(GODOT_CONFIG, () => {
\t\t\tsetStatusMode('progress');
\t\t\treturn engine.startGame({"""
LEGACY_PATCHED_END = """\t\t}, displayFailureNotice);
\t\t}, (message) => {
\t\t\tsetStatusNotice(message);
\t\t\tsetStatusMode('notice');
\t\t\treturn statusNotice;
\t\t});"""
PATCHED_END = """\t\t}, (error) => {
\t\t\tdisplayFailureNotice(error);
\t\t\tthrow error;
\t\t});
\t\t}, (message) => {
\t\t\tsetStatusNotice(message);
\t\t\tsetStatusMode('notice');
\t\t\treturn statusNotice;
\t\t});"""


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError(f"Duplicate GODOT_CONFIG key: {key}")
        result[key] = value
    return result


def invalid_constant(value):
    raise ValueError(f"Invalid GODOT_CONFIG constant: {value}")


def transform(html: str) -> str:
    patched = SCRIPT_NAME in html or "rdStartWithSessionLock" in html
    original = html
    previous_end = None
    if patched:
        endings = [end for end in (PATCHED_END, LEGACY_PATCHED_END) if original.count(end) == 1]
        if len(endings) != 1:
            raise ValueError("Unrecognized Web session lock wrapper")
        previous_end = endings[0]
        for anchor in (SCRIPT_TAG, PATCHED_START, previous_end):
            if original.count(anchor) != 1:
                raise ValueError("Incomplete or duplicate Web session lock patch")
        original = original.replace(SCRIPT_TAG, "", 1)
        original = original.replace(PATCHED_START, START, 1).replace(previous_end, END, 1)
    scripts = list(re.finditer(r"<script\b([^>]*)>(.*?)</script\s*>", original, re.DOTALL))
    if len(scripts) != 2 or scripts[0].group(1) != ' src="index.js"' or scripts[0].group(2) != "" or scripts[1].group(1) != "":
        raise ValueError("Unexpected Web shell script layout")
    if original.count(ENGINE_TAG) != 1 or original.count(START) != 1 or original.count(END) != 1:
        raise ValueError("Unexpected Web shell startup anchors")
    body = scripts[1].group(2)
    prefix = "const GODOT_CONFIG = "
    if body.count(prefix) != 1 or body.count("new Engine(GODOT_CONFIG)") != 1:
        raise ValueError("Unexpected GODOT_CONFIG or Engine construction")
    value_start = body.index(prefix) + len(prefix)
    decoder = json.JSONDecoder(object_pairs_hook=unique_object, parse_constant=invalid_constant)
    config, value_end = decoder.raw_decode(body, value_start)
    if not isinstance(config, dict) or body[value_end:value_end + 2] != ";\n":
        raise ValueError("Unexpected GODOT_CONFIG value")
    if config.get("persistentPaths") not in PATHS:
        raise ValueError("Unrecognized persistentPaths; apply the stage configuration first")
    if config.get("serviceWorker", "") != "":
        raise ValueError("ServiceWorker startup requires separate session-lock review")
    normalized = body[:value_start] + "__RD_CONFIG__" + body[value_end:]
    if hashlib.sha256(normalized.encode("utf-8")).hexdigest() != INLINE_SHA256:
        raise ValueError("Unrecognized pinned Web shell; no changes made")
    result = original.replace(ENGINE_TAG, ENGINE_TAG + SCRIPT_TAG, 1)
    result = result.replace(START, PATCHED_START, 1).replace(END, PATCHED_END, 1)
    # 이전 wrapper도 원본 shell 해시를 통과한 경우에만 거부 전파 형태로 갱신한다.
    if previous_end == PATCHED_END and result != html:
        raise ValueError("Unexpected existing Web session lock patch")
    return result


def atomic_write(path: Path, data: bytes, expected: bytes | None) -> None:
    if path.is_symlink():
        raise ValueError(f"Refusing symbolic link output: {path}")
    mode = stat.S_IMODE(path.stat().st_mode) if path.exists() else 0o644
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(dir=path.parent, prefix=f".{path.name}.", suffix=".tmp", delete=False) as stream:
            temporary = Path(stream.name)
            stream.write(data)
            stream.flush()
            os.fsync(stream.fileno())
        temporary.chmod(mode)
        if path.is_symlink() or (path.read_bytes() if path.exists() else None) != expected:
            raise ValueError(f"Output changed during patching: {path}")
        os.replace(temporary, path)
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("html", type=Path, help="고정 템플릿에서 내보낸 index.html")
    args = parser.parse_args()
    try:
        if (ROOT / ".godot-version").read_text().strip() != "4.7.2-stable":
            raise ValueError("Godot version changed; Web session-lock review required")
        entrypoint = args.html
        destination = entrypoint.parent / SCRIPT_NAME
        if entrypoint.is_symlink() or destination.is_symlink():
            raise ValueError("Symbolic link Web outputs are not supported")
        original = entrypoint.read_bytes()
        updated = transform(original.decode("utf-8")).encode("utf-8")
        source = (ROOT / "scripts" / SCRIPT_NAME).read_bytes()
        existing = destination.read_bytes() if destination.exists() else None
        # HTML에서 참조하기 전에 보조 파일을 완성한다. HTML 자체는 마지막에 교체한다.
        if existing != source:
            atomic_write(destination, source, existing)
        if original != updated:
            atomic_write(entrypoint, updated, original)
        print(f"Web session lock verified: {entrypoint}")
    except (OSError, UnicodeError, ValueError) as error:
        parser.exit(1, f"Web session lock patch failed: {error}\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
