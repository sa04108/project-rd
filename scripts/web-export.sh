#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
STAGE="production"
DEST=""
while (( $# )); do
	case "$1" in
		--stage)
			(( $# >= 2 )) || { echo '--stage requires production or development' >&2; exit 2; }
			STAGE="$2"; shift 2 ;;
		--help|-h)
			echo 'Usage: bash scripts/web-export.sh [--stage production|development] [destination]'
			exit 0 ;;
		-*) echo "Unknown argument: $1" >&2; exit 2 ;;
		*)
			[[ -z "$DEST" ]] || { echo 'Only one export destination is allowed' >&2; exit 2; }
			DEST="$1"; shift ;;
	esac
done
case "$STAGE" in
	production) DEFAULT_DEST="$ROOT/artifacts/web" ;;
	development) DEFAULT_DEST="$ROOT/artifacts/web/development" ;;
	*) echo '--stage must be production or development' >&2; exit 2 ;;
esac
MODE="${WEB_EXPORT_MODE:-release}"
case "$MODE" in
	debug) FLAG="--export-debug" ;;
	release) FLAG="--export-release" ;;
	*) echo 'WEB_EXPORT_MODE must be debug or release' >&2; exit 2 ;;
esac
DEST="${DEST:-$DEFAULT_DEST}"
VERSION="$(tr -d '\r\n' < "$ROOT/.godot-version")"
GODOT="${GODOT_BIN:-$ROOT/.godot-tools/$VERSION/godot}"
[[ -x "$GODOT" && -f "$ROOT/project.godot" ]] || { echo 'Pinned Godot binary or project.godot is missing' >&2; exit 1; }
[[ "$($GODOT --version)" == "${VERSION%-stable}.stable."* ]] || { echo 'Godot binary does not match .godot-version' >&2; exit 1; }
export PATH="$ROOT/.godot-tools/os/usr/bin:$PATH"
export XDG_DATA_HOME="$ROOT/artifacts/user-data"
export XDG_CONFIG_HOME="$ROOT/artifacts/user-config"
export XDG_CACHE_HOME="$ROOT/artifacts/user-cache"
export GODOT_SILENCE_ROOT_WARNING=1
mkdir -p "$ROOT/artifacts/logs" "$XDG_DATA_HOME" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME" "$ROOT/artifacts/stage-build"
touch "$ROOT/artifacts/.gdignore"
BUILD_WORK="$(mktemp -d "$ROOT/artifacts/stage-build/web-$STAGE.XXXXXX")"
BUILD_PROJECT="$BUILD_WORK/project"
cleanup() {
	case "$BUILD_WORK" in
		"$ROOT/artifacts/stage-build/web-$STAGE."*) rm -rf -- "$BUILD_WORK" ;;
	esac
}
trap cleanup EXIT
run_logged() {
	local name="$1"; shift
	local log="$ROOT/artifacts/logs/$name.log" status=0
	"$@" >"$log" 2>&1 || status=$?
	cat "$log"
	if (( status != 0 )); then echo "$name failed with exit $status" >&2; return "$status"; fi
	if rg -n 'SCRIPT ERROR:|(^|[[:space:]])ERROR:|Parse Error:' "$log"; then
		echo "$name contains a Godot error" >&2; return 1
	fi
}

run_logged "web-$STAGE-stage" python3 "$ROOT/scripts/stage-build.py" --stage "$STAGE" --output "$BUILD_PROJECT"
bash "$ROOT/scripts/web-setup.sh"

mkdir -p "$DEST"
DEST="$(cd "$DEST" && pwd)"

run_logged "web-$STAGE-import" timeout --kill-after=5s 180s "$GODOT" --headless --path "$BUILD_PROJECT" --editor --import
run_logged "web-$STAGE-export" timeout --kill-after=5s 180s "$GODOT" --headless --path "$BUILD_PROJECT" "$FLAG" "Web Preview" "$DEST/index.html"
run_logged "web-$STAGE-runtime" python3 "$ROOT/scripts/web-patch-gl-tables.py" "$DEST/index.js" \
	--mode "$MODE" --template "$XDG_DATA_HOME/godot/export_templates/${VERSION%-stable}.stable/web_nothreads_${MODE}.zip"
test -s "$DEST/index.html"
shopt -s nullglob
WASM=("$DEST"/*.wasm)
PACK=("$DEST"/*.pck)
(( ${#WASM[@]} == 1 )) || { echo "Expected one WebAssembly module in $DEST" >&2; exit 1; }
(( ${#PACK[@]} == 1 )) || { echo "Expected one PCK content pack in $DEST" >&2; exit 1; }
python3 - "$DEST" "$STAGE" "$BUILD_PROJECT/project.godot" <<'PY'
import configparser
import json
import os
from pathlib import Path
import re
import sys
import tempfile

root = Path(sys.argv[1])
stage = sys.argv[2]
# Godot 4.7.2의 기본 user:// 경로와 저장소의 내부 이름을 함께 고정한다.
project = configparser.ConfigParser(interpolation=None, strict=True)
project.optionxform = str
project.read_string("[root]\n" + Path(sys.argv[3]).read_text(encoding="utf-8"))
application = project["application"]
name = json.loads(application.get("config/name", '""'))
storage_keys = ("config/name", "config/use_custom_user_dir", "config/custom_user_dir_name")
if any(key.startswith(base + ".") for key in application for base in storage_keys):
    raise SystemExit("Feature-specific user directory settings require Web persistence review")
if name != "project-rd · 용병 길드" or application.get("config/use_custom_user_dir", "false") != "false":
    raise SystemExit("Changed application user directory requires Web persistence review")
development_path = f"/userfs/godot/app_userdata/{name}/development"
paths_by_stage = {"production": ["/userfs"], "development": [development_path]}
if stage not in paths_by_stage:
    raise SystemExit(f"Invalid Web stage: {stage}")
entrypoint = root / "index.html"
html = entrypoint.read_text(encoding="utf-8")
for suffix in (".js", ".wasm", ".pck"):
    if suffix not in html:
        raise SystemExit(f"Web entrypoint does not reference expected {suffix} output")

# 고정 템플릿의 JSON 선언만 읽고 다시 직렬화해 서로 다른 IndexedDB 마운트를 확정한다.
declarations = list(re.finditer(r"\b(?:const|let|var)\s+GODOT_CONFIG\b", html))
assignments = list(re.finditer(r"\bGODOT_CONFIG\s*=(?!=)", html))
prefix = "const GODOT_CONFIG = "
if len(declarations) != 1 or len(assignments) != 1:
    raise SystemExit("Expected exactly one GODOT_CONFIG declaration and assignment")
start = declarations[0].start()
if not html.startswith(prefix, start):
    raise SystemExit("Unexpected GODOT_CONFIG declaration format")
value_start = start + len(prefix)

def unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError(f"Duplicate GODOT_CONFIG JSON key: {key}")
        result[key] = value
    return result

def invalid_constant(value):
    raise ValueError(f"Invalid GODOT_CONFIG JSON constant: {value}")

decoder = json.JSONDecoder(object_pairs_hook=unique_object, parse_constant=invalid_constant)
try:
    config, value_end = decoder.raw_decode(html, value_start)
except ValueError as error:
    raise SystemExit(f"Invalid GODOT_CONFIG JSON: {error}") from error
if not isinstance(config, dict) or html[value_end:value_end + 2] != ";\n":
    raise SystemExit("Expected a complete GODOT_CONFIG JSON object followed by a semicolon")
if html.count("new Engine(GODOT_CONFIG)") != 1 or html.index("new Engine(GODOT_CONFIG)") < value_end:
    raise SystemExit("Unexpected Engine initialization for GODOT_CONFIG")
paths = paths_by_stage[stage]
if "persistentPaths" in config and config["persistentPaths"] != paths:
    raise SystemExit("Existing persistentPaths conflicts with the selected build stage")
config["persistentPaths"] = paths
encoded = json.dumps(config, ensure_ascii=True, separators=(",", ":"), allow_nan=False).replace("<", "\\u003c")
updated = html[:value_start] + encoded + html[value_end:]
if updated != html:
    # 실패한 변환이 불완전한 HTML을 남기지 않도록 같은 디렉터리에서 원자적으로 교체한다.
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(mode="w", encoding="utf-8", dir=root, prefix=".index-stage-", suffix=".tmp", delete=False) as stream:
            temporary = Path(stream.name)
            stream.write(updated)
        temporary.chmod(entrypoint.stat().st_mode & 0o777)
        os.replace(temporary, entrypoint)
    finally:
        if temporary is not None and temporary.exists():
            temporary.unlink()
print(f"Web export verified: {root} ({stage}, persistentPaths={paths})")
PY

# 같은 스테이지의 두 탭이 각각 오래된 IDBFS 사본을 쓰지 않도록 엔진 시작을 보호한다.
python3 "$ROOT/scripts/web-patch-session-lock.py" "$DEST/index.html"
# 비동기 IDBFS 조회 도중 소유권을 잃은 경우에도 새 쓰기 거래를 만들지 않는다.
python3 "$ROOT/scripts/web-patch-session-runtime.py" "$DEST/index.js"
