#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
VERSION="$(tr -d '\r\n' < "$ROOT/.godot-version")"
GODOT="${GODOT_BIN:-$ROOT/.godot-tools/$VERSION/godot}"
[[ -x "$GODOT" && -f "$ROOT/project.godot" ]] || { echo 'Pinned Godot binary or project.godot is missing' >&2; exit 1; }
[[ "$($GODOT --version)" == "${VERSION%-stable}.stable."* ]] || { echo 'Godot binary does not match .godot-version' >&2; exit 1; }
export PATH="$ROOT/.godot-tools/os/usr/bin:$PATH"
export XDG_DATA_HOME="$ROOT/artifacts/user-data"
export XDG_CONFIG_HOME="$ROOT/artifacts/user-config"
export XDG_CACHE_HOME="$ROOT/artifacts/user-cache"
export GODOT_SILENCE_ROOT_WARNING=1
mkdir -p "$ROOT/artifacts/logs" "$XDG_DATA_HOME" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME" "$ROOT/artifacts/web"
touch "$ROOT/artifacts/.gdignore"
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

bash "$ROOT/scripts/web-setup.sh"

DEST="${1:-$ROOT/artifacts/web}"
mkdir -p "$DEST"
DEST="$(cd "$DEST" && pwd)"
MODE="${WEB_EXPORT_MODE:-release}"
case "$MODE" in
	debug) FLAG="--export-debug" ;;
	release) FLAG="--export-release" ;;
	*) echo 'WEB_EXPORT_MODE must be debug or release' >&2; exit 2 ;;
esac

run_logged web-import timeout --kill-after=5s 180s "$GODOT" --headless --path "$ROOT" --editor --import
run_logged web-export timeout --kill-after=5s 180s "$GODOT" --headless --path "$ROOT" "$FLAG" "Web Preview" "$DEST/index.html"
run_logged web-runtime python3 "$ROOT/scripts/web-patch-gl-tables.py" "$DEST/index.js" \
	--mode "$MODE" --template "$XDG_DATA_HOME/godot/export_templates/${VERSION%-stable}.stable/web_nothreads_${MODE}.zip"
test -s "$DEST/index.html"
shopt -s nullglob
WASM=("$DEST"/*.wasm)
PACK=("$DEST"/*.pck)
(( ${#WASM[@]} == 1 )) || { echo "Expected one WebAssembly module in $DEST" >&2; exit 1; }
(( ${#PACK[@]} == 1 )) || { echo "Expected one PCK content pack in $DEST" >&2; exit 1; }
python3 - "$DEST" <<'PY'
from pathlib import Path
import sys

root = Path(sys.argv[1])
html = (root / "index.html").read_text(encoding="utf-8")
for suffix in (".js", ".wasm", ".pck"):
    if suffix not in html:
        raise SystemExit(f"Web entrypoint does not reference expected {suffix} output")
print(f"Web export verified: {root}")
PY
