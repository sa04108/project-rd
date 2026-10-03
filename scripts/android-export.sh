#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STAGE="production"
while (( $# )); do
	case "$1" in
		--stage)
			(( $# >= 2 )) || { echo '--stage requires production or development' >&2; exit 2; }
			STAGE="$2"; shift 2 ;;
		--help|-h)
			echo 'Usage: bash scripts/android-export.sh [--stage production|development]'
			exit 0 ;;
		*) echo "Unknown argument: $1" >&2; exit 2 ;;
	esac
done
case "$STAGE" in
	production) APK="$ROOT/artifacts/android/project-rd-debug.apk" ;;
	development) APK="$ROOT/artifacts/android/project-rd-development-debug.apk" ;;
	*) echo '--stage must be production or development' >&2; exit 2 ;;
esac
TOOLS_ROOT="/workspace/.tools"
SDK_ROOT="$TOOLS_ROOT/android-sdk/sdk"
GODOT_VERSION="${GODOT_VERSION:-}"
if [[ -z "$GODOT_VERSION" ]]; then
	if [[ -f "$ROOT/.godot-version" ]]; then
		GODOT_VERSION="$(tr -d '\r\n' < "$ROOT/.godot-version")"
	else
		GODOT_VERSION="4.7.2-stable"
	fi
fi
GODOT="$ROOT/.godot-tools/$GODOT_VERSION/godot"
[[ "$GODOT_VERSION" == "$(tr -d '\r\n' < "$ROOT/.godot-version")" ]] || { echo 'Godot version does not match .godot-version' >&2; exit 1; }
[[ -x "$GODOT" ]] || { echo 'Pinned Godot binary is missing' >&2; exit 1; }
[[ "$($GODOT --version)" == "${GODOT_VERSION%-stable}.stable."* ]] || { echo 'Godot binary does not match .godot-version' >&2; exit 1; }
JAVA_BIN="$(readlink -f "$(command -v java)")"
export JAVA_HOME="$(dirname "$(dirname "$JAVA_BIN")")"
export ANDROID_HOME="$SDK_ROOT"
export ANDROID_SDK_ROOT="$SDK_ROOT"
export ANDROID_USER_HOME="$TOOLS_ROOT/android-sdk/user"
export XDG_DATA_HOME="$TOOLS_ROOT/godot-templates/data"
export XDG_CONFIG_HOME="$TOOLS_ROOT/android-sdk/config"
export XDG_CACHE_HOME="$TOOLS_ROOT/android-sdk/cache"
export PATH="$SDK_ROOT/platform-tools:$SDK_ROOT/cmdline-tools/latest/bin:$PATH"

[[ -x "$GODOT" && -x "$SDK_ROOT/platform-tools/adb" ]]
mkdir -p "$ROOT/artifacts/android" "$ROOT/artifacts/logs" "$ROOT/artifacts/stage-build" "$XDG_CONFIG_HOME/godot" "$ANDROID_USER_HOME"
touch "$ROOT/artifacts/.gdignore"
BUILD_WORK="$(mktemp -d "$ROOT/artifacts/stage-build/android-$STAGE.XXXXXX")"
BUILD_PROJECT="$BUILD_WORK/project"
cleanup() {
	case "$BUILD_WORK" in
		"$ROOT/artifacts/stage-build/android-$STAGE."*) rm -rf -- "$BUILD_WORK" ;;
	esac
}
trap cleanup EXIT
python3 "$ROOT/scripts/stage-build.py" --stage "$STAGE" --output "$BUILD_PROJECT"
python3 - "$XDG_CONFIG_HOME/godot/editor_settings-4.7.tres" "$SDK_ROOT" "$JAVA_HOME" <<'PYSETTINGS'
from pathlib import Path
import sys

path = Path(sys.argv[1])
values = {
    "export/android/android_sdk_path": sys.argv[2],
    "export/android/java_sdk_path": sys.argv[3],
}
lines = path.read_text().splitlines() if path.exists() else [
    '[gd_resource type="EditorSettings" format=3]',
    "",
    "[resource]",
]
for key, value in values.items():
    setting = f'{key} = "{value}"'
    matches = [index for index, line in enumerate(lines) if line.startswith(key + " =")]
    if matches:
        lines[matches[0]] = setting
        for duplicate in reversed(matches[1:]):
            del lines[duplicate]
    else:
        lines.append(setting)
path.parent.mkdir(parents=True, exist_ok=True)
path.write_text("\n".join(lines) + "\n")
PYSETTINGS

"$GODOT" --headless --editor --path "$BUILD_PROJECT" --import
"$GODOT" --headless --path "$BUILD_PROJECT" --export-debug "Android Debug" "$APK"
test -s "$APK"
"$SDK_ROOT/build-tools/35.0.0/aapt" dump badging "$APK" | rg -F "package: name='com.puzzlemind.frd'"
# Godot 4.7은 activity-alias에 런처를 선언하므로 구형 aapt badging 출력 대신 매니페스트를 읽는다.
"$SDK_ROOT/build-tools/35.0.0/aapt" dump xmltree "$APK" AndroidManifest.xml | rg -F 'android.intent.category.LAUNCHER'
python3 - "$APK" "$BUILD_PROJECT/assets/art/manifest.json" <<'PYAPK'
import json
import sys
import zipfile
from pathlib import Path

apk_path, manifest_path = map(Path, sys.argv[1:])
with zipfile.ZipFile(apk_path) as apk:
    names = set(apk.namelist())
    required = {
        "assets/data/game_rules.json",
        "assets/data/units.json",
        "assets/data/enemies.json",
        "assets/data/recipes.json",
        "assets/data/localization.json",
        "assets/assets/art/manifest.json",
    }
    missing = sorted(required - names)
    if missing:
        raise SystemExit(f"APK is missing required content: {missing}")
    manifest = json.loads(manifest_path.read_text())
    expected = {
        Path(entry["portrait_resource"]["path"]).name
        for entry in manifest.get("entries", [])
        if entry.get("portrait_resource", {}).get("distinct_per_catalog_entry") is True
    }
    imported = {
        Path(name).name.split("-", 1)[0]
        for name in names
        if name.startswith("assets/.godot/imported/") and name.endswith(".ctex")
    }
    absent_portraits = sorted(expected - imported)
    if len(expected) != 87 or absent_portraits:
        raise SystemExit(f"APK portrait coverage is {len(expected) - len(absent_portraits)}/87; missing={absent_portraits}")
    if any("/tests/" in name or name.startswith("assets/tests/") for name in names):
        raise SystemExit("APK unexpectedly contains test source files")
    if any("/sprite_run/raw/" in name for name in names):
        raise SystemExit("APK unexpectedly contains raw sprite sources")
print("APK content verified: gameplay/localization JSON files, art manifest, 87 portraits, no tests/raw sprites")
PYAPK
sha256sum "$APK"
