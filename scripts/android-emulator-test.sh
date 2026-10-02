#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TOOLS_ROOT="/workspace/.tools"
SDK_ROOT="$TOOLS_ROOT/android-sdk/sdk"
AVD_HOME="$TOOLS_ROOT/android-sdk/avd"
AVD_NAME="${ANDROID_AVD_NAME:-project-rd-api30-aosp-x86_64}"
APK="$ROOT/artifacts/android/project-rd-debug.apk"
ADB="$SDK_ROOT/platform-tools/adb"
EMULATOR="$SDK_ROOT/emulator/emulator"
XVFB_RUN="$ROOT/.godot-tools/os/usr/bin/xvfb-run"
PACKAGE="org.projectrd.debug"
DEVICE_SERIAL="emulator-5554"
BOOT_TIMEOUT="${ANDROID_EMULATOR_BOOT_TIMEOUT:-900}"
ADB_TIMEOUT="${ANDROID_ADB_TIMEOUT:-300}"
INSTALL_TIMEOUT="${ANDROID_INSTALL_TIMEOUT:-360}"
ANDROID_GPU="${ANDROID_GPU:-host}"
KEEP_ON_FAILURE="${ANDROID_KEEP_EMULATOR_ON_FAILURE:-0}"
QA_TIMEOUT="${ANDROID_QA_TIMEOUT:-120}"
QA_STATUS=1

test -x "$ADB" && test -x "$EMULATOR" && test -s "$APK" && command -v setsid >/dev/null
RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)-$$"
LOG_DIR="$ROOT/artifacts/logs/android-qa/$RUN_ID"
mkdir -p "$LOG_DIR" "$ROOT/artifacts/screenshots/android/$RUN_ID"
EMULATOR_LOG="$LOG_DIR/emulator.log"
LOGCAT_FILE="$LOG_DIR/logcat.txt"
SCREENSHOT_DIR="$ROOT/artifacts/screenshots/android/$RUN_ID"
MANIFEST="$LOG_DIR/run-manifest.json"
APK_SHA256="$(sha256sum "$APK" | awk '{print $1}')"
ANDROID_API_ACTUAL="$(sed -n 's/^target=android-//p' "$AVD_HOME/$AVD_NAME.avd/config.ini" | head -n 1)"
GODOT_VERSION_ACTUAL="${GODOT_VERSION:-}"
if [[ -z "$GODOT_VERSION_ACTUAL" ]]; then
	if [[ -f "$ROOT/.godot-version" ]]; then
		GODOT_VERSION_ACTUAL="$(tr -d '\r\n' < "$ROOT/.godot-version")"
	else
		GODOT_VERSION_ACTUAL="4.4.1-stable"
	fi
fi
SDK_TOOLS_REVISION="$(sed -n 's/^Pkg.Revision=//p' "$SDK_ROOT/cmdline-tools/latest/source.properties" | head -n 1)"
python3 - "$MANIFEST" "$RUN_ID" "$APK_SHA256" "$PACKAGE" "$AVD_NAME" "$ANDROID_API_ACTUAL" "$ANDROID_GPU" "$SDK_TOOLS_REVISION" "$GODOT_VERSION_ACTUAL" <<'PYMANIFEST'
import json
import sys
from pathlib import Path

path, run_id, apk_sha, package, avd, api, gpu, sdk_tools, godot = sys.argv[1:]
Path(path).write_text(json.dumps({
    "run_id": run_id, "apk_sha256": apk_sha, "package": package, "avd": avd,
    "android_api": int(api), "gpu_backend": gpu, "android_command_line_tools": sdk_tools,
    "godot": godot, "exit_status": None,
}, indent=2) + "\n")
PYMANIFEST
export ANDROID_HOME="$SDK_ROOT"
export ANDROID_SDK_ROOT="$SDK_ROOT"
export ANDROID_AVD_HOME="$AVD_HOME"
export ANDROID_SERIAL="$DEVICE_SERIAL"
export PATH="$SDK_ROOT/platform-tools:$PATH"

timeout "$ADB_TIMEOUT" "$ADB" start-server >/dev/null
if ! devices="$(timeout 15 "$ADB" devices)"; then
	echo "Could not inspect adb devices before emulator launch" >&2
	exit 2
fi
if printf '%s\n' "$devices" | awk -v serial="$DEVICE_SERIAL" '$1 == serial { found = 1 } END { exit !found }'; then
	echo "Refusing to replace existing Android target $DEVICE_SERIAL" >&2
	exit 2
fi
ACCEL_ARGS=(-accel off)
if [[ -r /dev/kvm && -w /dev/kvm ]]; then
	ACCEL_ARGS=(-accel on)
fi
EMULATOR_ARGS=(-avd "$AVD_NAME" -port 5554 -no-audio -no-boot-anim \
	-memory 3072 -cores 2 "${ACCEL_ARGS[@]}")
if [[ "$ANDROID_GPU" == "host" ]]; then
	test -x "$XVFB_RUN"
	PATH="$ROOT/.godot-tools/os/usr/bin:$PATH" setsid "$XVFB_RUN" -a -s '-screen 0 1280x720x24' \
		env LIBGL_ALWAYS_SOFTWARE=1 "$EMULATOR" "${EMULATOR_ARGS[@]}" -gpu host -no-snapshot \
		> "$EMULATOR_LOG" 2>&1 &
else
	setsid "$EMULATOR" "${EMULATOR_ARGS[@]}" -no-window -gpu "$ANDROID_GPU" \
		> "$EMULATOR_LOG" 2>&1 &
fi
EMULATOR_PID=$!
EMULATOR_PGID=""
for ((attempt = 0; attempt < 100; attempt++)); do
	EMULATOR_PGID="$(ps -o pgid= -p "$EMULATOR_PID" 2>/dev/null | tr -d ' ' || true)"
	[[ "$EMULATOR_PGID" == "$EMULATOR_PID" ]] && break
	kill -0 "$EMULATOR_PID" 2>/dev/null || break
	sleep 0.02
done
cleanup() {
	local command_status=$?
	trap - EXIT
	QA_STATUS=$command_status
	timeout 30 "$ADB" -s "$DEVICE_SERIAL" logcat -d > "$LOGCAT_FILE" 2>/dev/null || true
	python3 - "$MANIFEST" "$QA_STATUS" <<'PYRESULT'
import json
import sys
from pathlib import Path

path, status = sys.argv[1:]
manifest = json.loads(Path(path).read_text())
manifest["exit_status"] = int(status)
Path(path).write_text(json.dumps(manifest, indent=2) + "\n")
PYRESULT
	if [[ "$KEEP_ON_FAILURE" == "1" && "$QA_STATUS" != "0" ]]; then
		echo "Keeping owned Android emulator $DEVICE_SERIAL for failure diagnosis" >&2
		return
	fi
	if [[ -n "$EMULATOR_PID" ]]; then
		if [[ "$EMULATOR_PGID" == "$EMULATOR_PID" ]]; then
			if ps -eo pgid=,stat= | awk -v group="$EMULATOR_PGID" '$1 == group && $2 !~ /^Z/ { found=1 } END { exit !found }'; then
				timeout 20 "$ADB" -s "$DEVICE_SERIAL" emu kill >/dev/null 2>&1 || true
			fi
			for ((attempt = 0; attempt < 100; attempt++)); do
				live_members="$(ps -eo pgid=,stat= | awk -v group="$EMULATOR_PGID" '$1 == group && $2 !~ /^Z/ { count++ } END { print count+0 }')"
				[[ "$live_members" != 0 ]] || break
				sleep 0.2
			done
			if [[ "${live_members:-0}" != 0 ]]; then
				kill -TERM -- "-$EMULATOR_PGID" 2>/dev/null || true
				sleep 1
				live_members="$(ps -eo pgid=,stat= | awk -v group="$EMULATOR_PGID" '$1 == group && $2 !~ /^Z/ { count++ } END { print count+0 }')"
				if [[ "$live_members" != 0 ]]; then kill -KILL -- "-$EMULATOR_PGID" 2>/dev/null || true; fi
			fi
		else
			echo "Emulator process group mismatch; stopping only owned launcher pid=$EMULATOR_PID" >&2
			kill -TERM "$EMULATOR_PID" 2>/dev/null || true
		fi
		wait "$EMULATOR_PID" 2>/dev/null || true
	fi
}
trap cleanup EXIT
if [[ "$EMULATOR_PGID" != "$EMULATOR_PID" ]]; then
	echo "Could not establish isolated emulator process group (pid=$EMULATOR_PID pgid=$EMULATOR_PGID)" >&2
	exit 1
fi

timeout "$BOOT_TIMEOUT" "$ADB" -s "$DEVICE_SERIAL" wait-for-device
deadline=$((SECONDS + BOOT_TIMEOUT))
while (( SECONDS < deadline )); do
	booted="$(timeout 15 "$ADB" -s "$DEVICE_SERIAL" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r' || true)"
	if [[ "$booted" == "1" ]]; then
		break
	fi
	sleep 2
done
[[ "$(timeout 15 "$ADB" -s "$DEVICE_SERIAL" shell getprop sys.boot_completed | tr -d '\r' || true)" == "1" ]] || {
	cat "$EMULATOR_LOG" >&2
	echo "Android emulator did not finish booting in ${BOOT_TIMEOUT} seconds" >&2
	exit 1
}

timeout 30 "$ADB" -s "$DEVICE_SERIAL" logcat -c
timeout "$INSTALL_TIMEOUT" "$ADB" -s "$DEVICE_SERIAL" install --no-streaming -r "$APK"
timeout 90 "$ADB" -s "$DEVICE_SERIAL" shell pm clear "$PACKAGE" >/dev/null
timeout 60 "$ADB" -s "$DEVICE_SERIAL" shell monkey -p "$PACKAGE" 1
sleep 5
set +e
ANDROID_QA_TIMEOUT="$QA_TIMEOUT" python3 "$ROOT/tools/android/qa_driver.py" --adb "$ADB" --package "$PACKAGE" --output "$LOG_DIR" --screenshots "$SCREENSHOT_DIR" 2>&1 | tee "$LOG_DIR/qa-driver.log"
QA_STATUS=${PIPESTATUS[0]}
set -e
timeout 30 "$ADB" -s "$DEVICE_SERIAL" logcat -d > "$LOGCAT_FILE"
if rg -n -i 'SCRIPT ERROR:|Parse Error:|Failed to load script|JSON.{0,40}(parse|error|fail)|godot.*ERROR:' "$LOGCAT_FILE" > "$LOG_DIR/runtime-script-errors.txt"; then
	cat "$LOG_DIR/runtime-script-errors.txt" >&2
	QA_STATUS=1
fi
echo "Android emulator QA run $RUN_ID: $LOG_DIR and $SCREENSHOT_DIR"
exit "$QA_STATUS"
