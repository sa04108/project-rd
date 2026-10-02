#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TOOLS_ROOT="/workspace/.tools"
SDK_ROOT="$TOOLS_ROOT/android-sdk/sdk"
SDK_DOWNLOADS="$TOOLS_ROOT/android-sdk/downloads"
GODOT_DATA="$TOOLS_ROOT/godot-templates/data"
TEMPLATE_DOWNLOADS="$TOOLS_ROOT/godot-templates/downloads/4.7.2-stable"
GODOT_VERSION="${GODOT_VERSION:-}"
if [[ -z "$GODOT_VERSION" ]]; then
	if [[ -f "$ROOT/.godot-version" ]]; then
		GODOT_VERSION="$(tr -d '\r\n' < "$ROOT/.godot-version")"
	else
		GODOT_VERSION="4.7.2-stable"
	fi
fi
ANDROID_API="${ANDROID_API:-30}"
ANDROID_SYSTEM_IMAGE="${ANDROID_SYSTEM_IMAGE:-system-images;android-${ANDROID_API};default;x86_64}"
AVD_NAME="${ANDROID_AVD_NAME:-project-rd-api${ANDROID_API}-aosp-x86_64}"
CMDLINE_ARCHIVE="commandlinetools-linux-16111833_latest.zip"
CMDLINE_SHA1="e025545c62a8e64c7559119566a569fb1dec5f60"
TEMPLATE_ARCHIVE="Godot_v${GODOT_VERSION}_export_templates.tpz"

for tool in curl sha1sum sha512sum unzip java python3; do
	command -v "$tool" >/dev/null
done
[[ "$GODOT_VERSION" == "4.7.2-stable" && "$(uname -m)" == "x86_64" ]]
mkdir -p "$SDK_DOWNLOADS" "$SDK_ROOT" "$TEMPLATE_DOWNLOADS"

if [[ ! -x "$SDK_ROOT/cmdline-tools/latest/bin/sdkmanager" ]]; then
	archive="$SDK_DOWNLOADS/$CMDLINE_ARCHIVE"
	if [[ ! -f "$archive" ]]; then
		curl -fL --retry 3 "https://dl.google.com/android/repository/$CMDLINE_ARCHIVE" -o "$archive"
	fi
	printf '%s  %s\n' "$CMDLINE_SHA1" "$archive" | sha1sum -c -
	tmp="$(mktemp -d)"
	trap 'rm -rf "$tmp"' EXIT
	unzip -q "$archive" -d "$tmp"
	mkdir -p "$SDK_ROOT/cmdline-tools/latest"
	cp -a "$tmp/cmdline-tools/." "$SDK_ROOT/cmdline-tools/latest/"
fi

SDKMANAGER="$SDK_ROOT/cmdline-tools/latest/bin/sdkmanager"
export ANDROID_HOME="$SDK_ROOT"
export ANDROID_SDK_ROOT="$SDK_ROOT"
mkdir -p "$SDK_ROOT/licenses"
set +e
yes | "$SDKMANAGER" --sdk_root="$SDK_ROOT" --licenses >/dev/null
sdk_license_status=${PIPESTATUS[1]}
set -e
if (( sdk_license_status != 0 )); then
	exit "$sdk_license_status"
fi
"$SDKMANAGER" --sdk_root="$SDK_ROOT" --install \
	'platform-tools' \
	'platforms;android-35' \
	'build-tools;35.0.0' \
	'emulator' \
	"$ANDROID_SYSTEM_IMAGE"
test -s "$SDK_ROOT/licenses/android-sdk-license"
test -x "$SDK_ROOT/platform-tools/adb"
test -x "$SDK_ROOT/emulator/emulator"
SYSTEM_IMAGE_PATH="${ANDROID_SYSTEM_IMAGE#system-images;}"
SYSTEM_IMAGE_PATH="${SYSTEM_IMAGE_PATH//;/\/}"
test -f "$SDK_ROOT/system-images/$SYSTEM_IMAGE_PATH/system.img"

TEMPLATE_DIR="$GODOT_DATA/godot/export_templates/4.7.2.stable"
TEMPLATE_PATH="$TEMPLATE_DOWNLOADS/$TEMPLATE_ARCHIVE"
if [[ ! -f "$TEMPLATE_PATH" ]]; then
	curl -fL --retry 3 "https://github.com/godotengine/godot/releases/download/$GODOT_VERSION/$TEMPLATE_ARCHIVE" -o "$TEMPLATE_PATH"
fi
if [[ ! -f "$TEMPLATE_DOWNLOADS/SHA512-SUMS.txt" ]]; then
	curl -fsSL --retry 3 "https://github.com/godotengine/godot/releases/download/$GODOT_VERSION/SHA512-SUMS.txt" -o "$TEMPLATE_DOWNLOADS/SHA512-SUMS.txt"
fi
grep -E "^[[:xdigit:]]{128}[[:space:]]+\*?$TEMPLATE_ARCHIVE$" "$TEMPLATE_DOWNLOADS/SHA512-SUMS.txt" > "$TEMPLATE_DOWNLOADS/selected.sha512"
test "$(wc -l < "$TEMPLATE_DOWNLOADS/selected.sha512")" = 1
(cd "$TEMPLATE_DOWNLOADS" && sha512sum -c selected.sha512)
mkdir -p "$TEMPLATE_DIR"
for name in android_debug.apk android_release.apk android_source.zip icudt_godot.dat version.txt; do
	if [[ ! -f "$TEMPLATE_DIR/$name" ]]; then
		unzip -p "$TEMPLATE_PATH" "templates/$name" > "$TEMPLATE_DIR/$name"
	fi
done
test "$(cat "$TEMPLATE_DIR/version.txt")" = "4.7.2.stable"

AVD_HOME="$TOOLS_ROOT/android-sdk/avd"
export ANDROID_AVD_HOME="$AVD_HOME"
mkdir -p "$AVD_HOME"
AVDMANAGER="$SDK_ROOT/cmdline-tools/latest/bin/avdmanager"
if ! "$AVDMANAGER" list avd | rg -q "Name: $AVD_NAME"; then
	"$AVDMANAGER" create avd --force --name "$AVD_NAME" \
		--package "$ANDROID_SYSTEM_IMAGE" --device pixel_2 <<<'no'
fi
AVD_CONFIG="$AVD_HOME/$AVD_NAME.avd/config.ini"
python3 - "$AVD_CONFIG" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
values = {
    "hw.lcd.width": "720",
    "hw.lcd.height": "1280",
    "hw.lcd.density": "320",
    "hw.ramSize": "3072",
    "hw.gpu.enabled": "yes",
	"hw.gpu.mode": "host",
}
lines = path.read_text().splitlines() if path.exists() else []
lines = [line for line in lines if line.split("=", 1)[0] not in values]
lines.extend(f"{key}={value}" for key, value in values.items())
path.write_text("\n".join(lines) + "\n")
PY

printf 'Android SDK root: %s\n' "$SDK_ROOT"
printf 'Godot template directory: %s\n' "$TEMPLATE_DIR"
printf 'Android emulator: '
"$SDK_ROOT/emulator/emulator" -version | head -n 1
printf 'ADB: '
"$SDK_ROOT/platform-tools/adb" version | head -n 2 | tail -n 1
printf 'AVD: %s (%s, x86_64, 720x1280)\n' "$AVD_NAME" "$ANDROID_SYSTEM_IMAGE"
