#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TOOLS_ROOT="/workspace/.tools"
SDK_ROOT="$TOOLS_ROOT/android-sdk/sdk"
GODOT_VERSION="${GODOT_VERSION:-}"
if [[ -z "$GODOT_VERSION" ]]; then
	if [[ -f "$ROOT/.godot-version" ]]; then
		GODOT_VERSION="$(tr -d '\r\n' < "$ROOT/.godot-version")"
	else
		GODOT_VERSION="4.4.1-stable"
	fi
fi
GODOT="$ROOT/.godot-tools/$GODOT_VERSION/godot"
JAVA_BIN="$(readlink -f "$(command -v java)")"
export JAVA_HOME="$(dirname "$(dirname "$JAVA_BIN")")"
export ANDROID_HOME="$SDK_ROOT"
export ANDROID_SDK_ROOT="$SDK_ROOT"
export XDG_DATA_HOME="$TOOLS_ROOT/godot-templates/data"
export XDG_CONFIG_HOME="$TOOLS_ROOT/android-sdk/config"
export XDG_CACHE_HOME="$TOOLS_ROOT/android-sdk/cache"
export PATH="$SDK_ROOT/platform-tools:$SDK_ROOT/cmdline-tools/latest/bin:$PATH"

[[ -x "$GODOT" && -x "$SDK_ROOT/platform-tools/adb" ]]
mkdir -p "$ROOT/artifacts/android" "$ROOT/artifacts/logs" "$XDG_CONFIG_HOME/godot"
python3 - "$XDG_CONFIG_HOME/godot/editor_settings-4.4.tres" "$SDK_ROOT" "$JAVA_HOME" <<'PYSETTINGS'
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

"$GODOT" --headless --editor --path "$ROOT" --quit
"$GODOT" --headless --path "$ROOT" --export-debug "Android QA Debug" "$ROOT/artifacts/android/project-rd-debug.apk"
test -s "$ROOT/artifacts/android/project-rd-debug.apk"
"$SDK_ROOT/build-tools/35.0.0/aapt" dump badging "$ROOT/artifacts/android/project-rd-debug.apk" | rg -F "package: name='org.projectrd.debug'"
"$SDK_ROOT/build-tools/35.0.0/aapt" dump badging "$ROOT/artifacts/android/project-rd-debug.apk" | rg -F "launchable-activity:"
python3 - "$ROOT/artifacts/android/project-rd-debug.apk" "$ROOT/assets/art/manifest.json" <<'PYAPK'
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
print("APK content verified: four gameplay JSON files, art manifest, 87 portraits, no tests/raw sprites")
PYAPK
sha256sum "$ROOT/artifacts/android/project-rd-debug.apk"
