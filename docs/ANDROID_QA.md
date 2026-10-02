# Android debug QA

This workflow exports and runs the internal Android debug build on a local Android emulator or a connected test device. It does not create a release package or publish the app. The QA bridge runs only when the Android debug feature and `--android-qa` argument are both present; it reports observations while all gameplay interactions use Android input events.

## Verified tools and host requirements

- Godot `4.4.1-stable`, with matching Android export templates verified against the official SHA-512 manifest.
- Android command-line tools `23.0` (installed `Pkg.Revision` from `source.properties`; downloaded archive `commandlinetools-linux-16111833_latest.zip`), platform-tools `37.0.1`, emulator `37.2.12`, Build Tools `35.0.0`.
- Default device: Android API `30`, AOSP default x86_64 system image revision `11`, AVD `project-rd-api30-aosp-x86_64`. API 35 Google APIs first boot did not complete reliably under TCG on this host.
- Java 21, Python 3, `curl`, `unzip`, and standard shell tools.
- The host must support Android x86_64 emulation. With `/dev/kvm`, the runner enables hardware acceleration; otherwise it uses TCG. The verified configuration uses the emulator's `host` GPU mode under Xvfb with `LIBGL_ALWAYS_SOFTWARE=1`; logcat reported Mesa 25 llvmpipe as the Android GLES renderer. TCG is much slower and is intended for smoke/lifecycle checks.

Dependencies are cached outside the checkout at `/workspace/.tools/android-sdk` and `/workspace/.tools/godot-templates`. Google SDK package licenses are accepted by `sdkmanager` during setup. Downloads retain TLS and checksum verification.

## Setup and export

From `/workspace/project-rd`:

```sh
bash scripts/android-setup.sh
bash scripts/android-export.sh
```

The export is the signed debug APK `artifacts/android/project-rd-debug.apk`, package `org.projectrd.debug`, using the `Android QA Debug` export preset. The preset passes `--android-qa`, uses the isolated `user://android-qa` save directory and deterministic QA seed, and disables sound. It is not a release build. The export script verifies the APK package and launcher activity and prints its SHA-256.

## Emulator QA

```sh
bash scripts/android-emulator-test.sh
```

The script boots the configured AVD at 720×1280 with the host/Xvfb/llvmpipe path, installs the APK, clears only that app's emulator data, and runs `tools/android/qa_driver.py`. The driver uses adb taps/swipes and Android's built-in UIAutomator hierarchy dump. It checks that the app owns the foreground activity and that Android's System UI ANR dialog is absent before it starts tapping. It exercises back navigation, a fresh run, three summons, pause/speed, recipe panel, unit drag/swap, background/resume time handling, save-to-menu, continue, and force-stop/relaunch persistence. Screenshots at the menu, recipe panel, resumed battle, and process-restart battle must contain visible pixel diversity. The runner scans Godot engine errors and cleans up only its own emulator process group. Set `ANDROID_GPU` to select another official emulator backend (`host` uses Xvfb; `swiftshader` and `software` use headless mode), `ANDROID_AVD_NAME` to select another image, `ANDROID_EMULATOR_BOOT_TIMEOUT` for boot waiting (default 900 seconds), `ANDROID_ADB_TIMEOUT` for adb startup/wait commands (default 300 seconds), `ANDROID_INSTALL_TIMEOUT` for APK installation (default 360 seconds), and `ANDROID_QA_TIMEOUT` for per-action waits (default 120 seconds). Set `ANDROID_KEEP_EMULATOR_ON_FAILURE=1` to leave the owned emulator running after a failed install or QA check for manual diagnosis.

The default setup selects the known-good API 30 AOSP image. To choose another image explicitly:

```sh
ANDROID_API=35 \
ANDROID_SYSTEM_IMAGE='system-images;android-35;google_apis;x86_64' \
ANDROID_AVD_NAME=project-rd-api35-x86_64 \
bash scripts/android-setup.sh
ANDROID_AVD_NAME=project-rd-api35-x86_64 ANDROID_GPU=swiftshader \
bash scripts/android-emulator-test.sh
```

The APK still targets the Godot template's Android API level; the emulator image version is reported in `qa-driver.log` and is the API level actually tested.

## Connected Android device

The same debug APK can be installed on a dedicated QA device. The automation currently uses touch coordinates for a 720×1280 display, so a device with another effective display size needs coordinate adaptation before its run can count as passing. These commands show the connection and launch steps; `pm clear` erases data only for the internal debug package:

```sh
ADB=/workspace/.tools/android-sdk/sdk/platform-tools/adb
export ANDROID_SERIAL='DEVICE_SERIAL'
"$ADB" devices -l
"$ADB" install -r artifacts/android/project-rd-debug.apk
"$ADB" shell pm clear org.projectrd.debug
"$ADB" shell monkey -p org.projectrd.debug 1
python3 tools/android/qa_driver.py \
  --adb "$ADB" \
  --package org.projectrd.debug \
  --output artifacts/logs/android-qa/physical-device \
  --screenshots artifacts/screenshots/android/physical-device
```

The driver captures screen diversity at the menu, recipe panel, resumed battle, and force-stop recovery; a uniform-color screen fails the visual-render check even if the QA state bridge responds. These checks do not establish a physical-device pass unless the driver completes on that device.

Logs, UI hierarchy XML, state JSON, and screenshots are written under `artifacts/logs/android-qa/` and `artifacts/screenshots/android/`. On failure, the emulator log and final adb logcat remain available in the log directory. Rerunning the test wipes the AVD's app data.

To inspect a live emulator manually, use the cached adb binary:

```sh
/workspace/.tools/android-sdk/sdk/platform-tools/adb devices -l
/workspace/.tools/android-sdk/sdk/platform-tools/adb shell run-as org.projectrd.debug cat files/qa_state.json
```

## Evidence limits

The 2026-10-02 GLES/SwiftShader run (`20261002T131654Z-24041`, APK SHA-256 `60e4262057c13f490fea3732f163e79910396027ab74248f07627b14614b1a1f`) passed 37 input, save, lifecycle, and restart checks, but its menu screenshot was uniform navy (720×1280, RGB 9/14/22 only). The emulated GLES device reports a 256-vector fragment uniform cap; Godot 4.4.1's canvas shader declares a 256-vector global-uniform array and five additional active uniforms, for a total of 261. The official GLES canvas renderer hard-codes that array size in [`rasterizer_canvas_gles3.cpp`](https://github.com/godotengine/godot/blob/4.4.1-stable/drivers/gles3/rasterizer_canvas_gles3.cpp#L2830); the separate RD `global_shader_variables/buffer_size` project setting does not control it. See [`android-gles-logic-only.json`](qa/android-gles-logic-only.json) for the logic-only run and shader evidence.

A Vulkan Mobile diagnostic APK (`artifacts/android/project-rd-vulkan-diagnostic.apk`, SHA-256 `5e78714f7a66f15d99ffecb8ddb72166983c10635f0dfec90637cf43404e5cf5`) crashed in SwiftShader during Vulkan startup (`goldfish-address-space mmap` failure followed by SIGSEGV on `VkThread`). Its post-crash screenshot is the Android launcher, not app-render evidence. See [`android-vulkan-diagnostic.json`](qa/android-vulkan-diagnostic.json).

The host/Xvfb/llvmpipe rerun (`20261002T140641Z-corrected-host`, APK SHA-256 `c2477ea903ad3793c026b475d87abf2143f41b130173d69ea267cfb6f20d7cca`) rendered the menu and battle correctly and passed 44 input, visual, save, lifecycle, and restart checks. Its final logcat had no Godot `ERROR`, script parse/load, JSON parse, Java fatal exception, or native crash matches. The final state restored three units, gold 120, wave 1, lives 20, speed 2, and the saved game time after force-stop/relaunch. Screenshots and logs are in `artifacts/screenshots/android/20261002T140641Z-corrected-host/` and `artifacts/logs/android-qa/20261002T140641Z-corrected-host/`; the complete manifest is `artifacts/logs/android-qa/20261002T140641Z-corrected-host/run-manifest.json`. The preceding same-device run had five Godot `can_process()` teardown errors; the UI removal fix was included in this verified APK.

API 35 Google APIs TCG boot failed in this environment; any successful AOSP API 30 run must be reported as API 30 only. Neither establishes performance, audio quality, or compatibility on a physical phone. This environment has no `/dev/kvm`; TCG startup may be slow or unavailable on some hosts. The QA bridge's `art_ready` field is runtime state and must not be treated as visual/art acceptance.
