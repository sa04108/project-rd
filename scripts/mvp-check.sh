#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
VERSION="$(tr -d '\r\n' < "$ROOT/.godot-version")"
GODOT="${GODOT_BIN:-$ROOT/.godot-tools/$VERSION/godot}"
[[ -x "$GODOT" ]] || { echo "Godot $VERSION 실행 파일을 GODOT_BIN으로 지정하세요." >&2; exit 1; }
export XDG_DATA_HOME="$ROOT/artifacts/user-data"
export XDG_CONFIG_HOME="$ROOT/artifacts/user-config"
export XDG_CACHE_HOME="$ROOT/artifacts/user-cache"
export PATH="$ROOT/.godot-tools/os/usr/bin:$PATH"
for tool in rg timeout; do
  command -v "$tool" >/dev/null || { echo "필수 검사 도구가 없습니다: $tool" >&2; exit 1; }
done
mkdir -p artifacts/logs "$XDG_DATA_HOME" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME"
touch artifacts/.gdignore
[[ "$("$GODOT" --version)" == "${VERSION%-stable}.stable."* ]] || { echo "Godot $VERSION 버전이 필요합니다." >&2; exit 1; }
run() {
  local label="$1"; shift
  local rc=0
  "$@" >"artifacts/logs/$label.log" 2>&1 || rc=$?
  if (( rc != 0 )) || rg -q 'SCRIPT ERROR:|(^|[[:space:]])ERROR:' "artifacts/logs/$label.log"; then
    cat "artifacts/logs/$label.log"
    return "$((rc == 0 ? 1 : rc))"
  fi
  echo "$label: PASS"
}
run mvp-import timeout --kill-after=5s 180s "$GODOT" --headless --path . --editor --import
run contracts timeout --kill-after=5s 60s "$GODOT" --headless --path . --script res://tests/run_cli.gd
rg -q '"failed":\[\]' artifacts/logs/contracts.log
run lifecycle timeout --kill-after=5s 60s "$GODOT" --headless --path . --script res://tests/lifecycle_regression.gd -- --ui-test
rg -Fq 'LIFECYCLE_REPORT {"failed":[]}' artifacts/logs/lifecycle.log
run audio timeout --kill-after=5s 60s "$GODOT" --headless --path . --script res://tests/audio_regression.gd -- --ui-test
rg -q '"failed":\[\]' artifacts/logs/audio.log
run identity-animation timeout --kill-after=5s 60s "$GODOT" --headless --path . --script res://tests/identity_animation_test.gd
rg -q '"failed":\[\]' artifacts/logs/identity-animation.log
run mvp-smoke timeout --kill-after=5s 60s "$GODOT" --headless --path . --quit-after 300
if [[ "${VERIFY_VISUAL:-0}" == 1 ]]; then
  run ui-scenario timeout --kill-after=5s 90s xvfb-run -a -s '-screen 0 900x1400x24' env LIBGL_ALWAYS_SOFTWARE=1 "$GODOT" --path . --audio-driver Dummy --rendering-method gl_compatibility --resolution 720x1280 --script res://tests/ui_scenario.gd -- --ui-test
  rg -q '"failed":0' artifacts/logs/ui-scenario.log
fi
