#!/usr/bin/env python3
"""실기기와 에뮬레이터에서 실제 터치 입력으로 Android QA 흐름을 검사한다."""
import argparse
import json
import os
import struct
import subprocess
import sys
import time
import xml.etree.ElementTree as ET
import zlib
from pathlib import Path


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--adb", required=True)
    parser.add_argument("--package", default="org.projectrd.debug")
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--screenshots", type=Path)
    parser.add_argument("--timeout", type=float, default=float(os.environ.get("ANDROID_QA_TIMEOUT", "35")))
    args = parser.parse_args()
    adb = [args.adb]
    args.output.mkdir(parents=True, exist_ok=True)
    screenshots = args.screenshots or args.output
    screenshots.mkdir(parents=True, exist_ok=True)
    checks: list[str] = []

    def run(*parts: str, timeout: int = 20, check: bool = True) -> str:
        result = subprocess.run(adb + list(parts), text=True, stdout=subprocess.PIPE,
                                stderr=subprocess.STDOUT, timeout=timeout)
        if check and result.returncode:
            raise RuntimeError(f"adb {' '.join(parts)} failed ({result.returncode}): {result.stdout}")
        return result.stdout.strip()

    def state() -> dict:
        raw = run("shell", "run-as", args.package, "cat", "files/qa_state.json", timeout=30)
        value = json.loads(raw)
        (args.output / "state-latest.json").write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n")
        return value

    def wait_for(predicate, label: str, timeout: float | None = None) -> dict:
        deadline = time.monotonic() + (args.timeout if timeout is None else timeout)
        latest = {}
        last_error = ""
        while time.monotonic() < deadline:
            try:
                latest = state()
                if predicate(latest):
                    return latest
                last_error = "predicate not yet true"
            except (RuntimeError, json.JSONDecodeError, OSError) as error:
                last_error = str(error)
            time.sleep(0.5)
        raise AssertionError(f"timeout waiting for {label}; latest={latest}; last_error={last_error}")

    def expect(condition: bool, label: str) -> None:
        if not condition:
            raise AssertionError(label)
        checks.append(label)
        print(f"PASS {label}", flush=True)

    def tap(x: int, y: int, settle: float = 0.65) -> None:
        run("shell", "input", "tap", str(x), str(y))
        time.sleep(settle)

    def action(name: str, settle: float = 0.65) -> None:
        # Godot이 관측한 실제 버튼 중심으로 Android 터치를 보낸다.
        button = state()["buttons"][name]
        if button["disabled"]:
            raise AssertionError(f"disabled action: {name}")
        tap(round(button["x"] + button["width"] / 2), round(button["y"] + button["height"] / 2), settle)

    def hierarchy(filename: str) -> tuple[int, str, set[str]]:
        run("shell", "uiautomator", "dump", "/sdcard/window.xml", timeout=30)
        run("pull", "/sdcard/window.xml", str(args.output / filename))
        tree = ET.parse(args.output / filename)
        nodes = list(tree.iter())
        text = " ".join(node.attrib.get("text", "") for node in nodes)
        packages = {node.attrib.get("package", "") for node in nodes if node.attrib.get("package")}
        return len(nodes), text, packages

    def app_is_foreground() -> bool:
        dump = run("shell", "dumpsys", "activity", "activities", timeout=30)
        resumed = next((line for line in dump.splitlines() if "mResumedActivity:" in line), "")
        return args.package in resumed

    def snapshot(filename: str) -> None:
        proc = subprocess.run(adb + ["exec-out", "screencap", "-p"], stdout=subprocess.PIPE,
                              stderr=subprocess.PIPE, timeout=30, check=True)
        (screenshots / filename).write_bytes(proc.stdout)

    def sampled_png_colors(path: Path) -> int:
        """PNG에서 화면의 실제 색상 분포를 읽어 단색 렌더 실패를 찾는다."""
        payload = path.read_bytes()
        if payload[:8] != b"\x89PNG\r\n\x1a\n":
            return 0
        offset, compressed, width, height, bit_depth, color_type, interlace = 8, bytearray(), 0, 0, 0, 0, 0
        while offset + 12 <= len(payload):
            length = struct.unpack_from(">I", payload, offset)[0]
            kind = payload[offset + 4:offset + 8]
            data = payload[offset + 8:offset + 8 + length]
            offset += length + 12
            if kind == b"IHDR":
                width, height, bit_depth, color_type, _, _, interlace = struct.unpack(">IIBBBBB", data)
            elif kind == b"IDAT":
                compressed.extend(data)
            elif kind == b"IEND":
                break
        if bit_depth != 8 or color_type not in (2, 6) or interlace != 0:
            return 0
        channels = 3 if color_type == 2 else 4
        stride = width * channels
        scanlines = zlib.decompress(compressed)
        previous = bytearray(stride)
        colors: set[tuple[int, ...]] = set()
        cursor = 0
        for y in range(height):
            filter_type = scanlines[cursor]
            row = bytearray(scanlines[cursor + 1:cursor + 1 + stride])
            cursor += stride + 1
            for i in range(stride):
                left = row[i - channels] if i >= channels else 0
                above = previous[i]
                upper_left = previous[i - channels] if i >= channels else 0
                if filter_type == 1:
                    row[i] = (row[i] + left) & 255
                elif filter_type == 2:
                    row[i] = (row[i] + above) & 255
                elif filter_type == 3:
                    row[i] = (row[i] + ((left + above) // 2)) & 255
                elif filter_type == 4:
                    estimate = left + above - upper_left
                    distances = (abs(estimate - left), abs(estimate - above), abs(estimate - upper_left))
                    predictor = left if distances[0] <= distances[1] and distances[0] <= distances[2] else (
                        above if distances[1] <= distances[2] else upper_left)
                    row[i] = (row[i] + predictor) & 255
                elif filter_type != 0:
                    return 0
            if y % max(1, height // 80) == 0:
                for x in range(0, width, max(1, width // 80)):
                    base = x * channels
                    colors.add(tuple(row[base:base + 3]))
                    if len(colors) > 16:
                        return len(colors)
            previous = row
        return len(colors)

    def verify_capture(filename: str, label: str) -> None:
        snapshot(filename)
        capture = screenshots / filename
        expect(capture.stat().st_size > 4096, label)
        color_count = sampled_png_colors(capture)
        expect(color_count > 16, f"{filename}에서 앱 화면 비단색 렌더링 확인: {color_count}색")

    # 첫 화면과 새 출정을 확인한 뒤 정확히 시작 골드만으로 용병 세 명을 부른다.
    initial = wait_for(lambda s: s.get("mode") == "menu", "초기 메뉴")
    expect(initial.get("android_qa") is True, "디버그 QA 브리지 활성화")
    expect(initial.get("frame_size") == [720, 1280], "세로 720x1280 화면")
    menu_nodes, menu_text, menu_packages = hierarchy("window-menu.xml")
    if "System UI isn't responding" in menu_text:
        tap(360, 716, 1.5)
        menu_nodes, menu_text, menu_packages = hierarchy("window-menu-after-wait.xml")
    if "System UI isn't responding" in menu_text:
        raise AssertionError("System UI ANR overlay remains after the single Wait action")
    expect(menu_nodes > 0 and app_is_foreground(), "Android QA 앱이 포그라운드에 표시됨")
    verify_capture("menu.png", "실제 Android 앱 메뉴 화면 캡처")
    action("new_game")
    wait_for(lambda s: s.get("mode") == "battle", "전투 진입")
    run("shell", "input", "keyevent", "4")
    back_settings = wait_for(lambda s: s.get("panel_name") == "settings", "전투 중 Android 뒤로가기 설정 패널")
    expect(back_settings.get("mode") == "battle", "전투 중 뒤로가기로 설정 패널 열기")
    run("shell", "input", "keyevent", "4")
    wait_for(lambda s: s.get("panel_name") == "", "두 번째 뒤로가기로 설정 패널 닫기")
    action("pause")
    paused = wait_for(lambda s: s.get("pause_reasons", {}).get("user") is True, "사용자 일시정지")
    expect(paused.get("result") == "active", "일시정지 중 전투 유지")
    for _ in range(3):
        action("summon", 0.35)
    current = wait_for(lambda s: len(s.get("units", [])) == 3, "용병 3회 소환")
    expect(len(current["units"]) == 3, "일시정지 뒤 시작 골드로 용병 3명 소환")
    expect(current["gold"] == 0, "시작 골드만으로 세 번 소환 후 골드 0")
    action("speed")
    speed = wait_for(lambda s: s.get("speed") == 2, "배속 전환")
    expect(speed.get("pause_reasons", {}).get("user") is True, "일시정지 상태에서 배속 변경")
    action("recipes")
    panel = wait_for(lambda s: s.get("panel_name") == "recipes", "조합법 패널")
    expect(panel.get("mode") == "battle", "조합법 패널에서 전투 장면 유지")
    recipe_nodes, _, _ = hierarchy("window-recipes.xml")
    expect(recipe_nodes > 0, "UIAutomator 조합 패널 계층 덤프 캡처")
    verify_capture("battle-recipes.png", "실제 Android 조합 패널 화면 캡처")
    action("close_panel")
    wait_for(lambda s: s.get("panel_name") == "", "패널 닫기")

    # 셀 0과 1에 둔 용병을 드래그 교환하고, 앱 백그라운드 시간은 전투에 반영되지 않는지 본다.
    before_units = {int(unit["id"]): int(unit["cell"]) for unit in current.get("units", [])}
    expect(0 in before_units.values() and 1 in before_units.values(), f"드래그 전 셀 0·1 점유: {before_units}")
    before_ids = {cell: unit_id for unit_id, cell in before_units.items()}
    expected_units = dict(before_units)
    expected_units[before_ids[0]], expected_units[before_ids[1]] = 1, 0
    cells = {cell["cell"]: cell for cell in state()["cell_centers"]}
    run("shell", "input", "swipe", str(round(cells[0]["x"])), str(round(cells[0]["y"])),
        str(round(cells[1]["x"])), str(round(cells[1]["y"])), "650")
    moved = wait_for(lambda s: {int(unit["id"]): int(unit["cell"]) for unit in s.get("units", [])} == expected_units,
                     "용병 두 칸 교환")
    after_units = {int(unit["id"]): int(unit["cell"]) for unit in moved.get("units", [])}
    expect(after_units == expected_units, f"드래그로 정확한 두 용병 교환: {after_units}")
    action("pause")
    active = wait_for(lambda s: not s.get("pause_reasons", {}).get("user", False), "전투 재개")
    run("shell", "input", "keyevent", "3")
    background = wait_for(lambda s: s.get("pause_reasons", {}).get("background") is True,
                          "백그라운드 일시정지 기록")
    first_background_time = float(background["time"])
    time.sleep(2.5)
    background_later = state()
    expect(background_later.get("pause_reasons", {}).get("background") is True,
           "후속 백그라운드 상태 확인")
    expect(abs(float(background_later["time"]) - first_background_time) < 0.15,
           "백그라운드 진입 상태끼리 게임 시간 정지")
    run("shell", "monkey", "-p", args.package, "1")
    resumed = wait_for(lambda s: not s.get("pause_reasons", {}).get("background", False), "앱 복귀")
    expect(resumed.get("mode") == "battle", "백그라운드 후 전투 복귀")
    verify_capture("battle-resumed.png", "백그라운드 복귀 전투 화면 캡처")

    # 설정 화면에서 저장 후 메뉴로 이동하고, 이어하기와 프로세스 재실행 저장을 검증한다.
    action("settings")
    wait_for(lambda s: s.get("panel_name") == "settings", "설정 패널")
    action("save_menu")
    menu = wait_for(lambda s: s.get("mode") == "menu", "저장 후 메뉴")
    expect(menu.get("snapshot_exists") is True, "저장 후 메뉴에서 스냅샷 존재")
    expect(len(menu.get("units", [])) == 3, "메뉴 진입 전 QA 관측에 용병 세 명 유지")
    saved_run = json.loads(run("shell", "run-as", args.package, "cat", "files/android-qa/run.json"))
    (args.output / "saved-run-before-resume.json").write_text(
        json.dumps(saved_run, ensure_ascii=False, indent=2) + "\n")
    expect(saved_run.get("gold") == menu.get("gold") and len(saved_run.get("units", [])) == 3,
           "저장 스냅샷의 골드와 세 용병 확인")
    menu_nodes, _, _ = hierarchy("window-saved-menu.xml")
    expect(menu_nodes > 0, "저장 메뉴 UI 계층 덤프 캡처")
    action("continue")
    battle = wait_for(lambda s: s.get("mode") == "battle", "이어하기 전투")
    def unit_summary(value: dict) -> list[tuple[int, str, int]]:
        return sorted((int(unit["id"]), str(unit["kind"]), int(unit["cell"])) for unit in value.get("units", []))
    expect(unit_summary(battle) == unit_summary(saved_run), "이어하기로 ID·종류·배치 복원")
    for field in ("gold", "lives", "wave", "speed"):
        expect(battle.get(field) == saved_run.get(field), f"이어하기로 {field} 복원")
    expect(abs(float(battle.get("time", 0)) - float(saved_run.get("time", 0))) < 0.01,
           "이어하기로 게임 시간 복원")
    old_pid = int(battle.get("process_id", -1))
    expect(old_pid > 0, "QA 상태에 Android 프로세스 ID 존재")
    run("shell", "am", "force-stop", args.package)
    time.sleep(1.0)
    run("shell", "monkey", "-p", args.package, "1")
    restarted = wait_for(lambda s: s.get("mode") == "menu" and int(s.get("process_id", -1)) != old_pid,
                         "새 프로세스의 메뉴 QA 상태")
    expect(restarted.get("snapshot_exists") is True, "프로세스 재시작 뒤 저장 스냅샷 유지")
    expect("" == restarted.get("save_error", ""), "프로세스 재시작 뒤 저장 오류 없음")
    restart_nodes, _, _ = hierarchy("window-process-restart.xml")
    expect(restart_nodes > 0, "재실행 메뉴 UI 계층 덤프 캡처")
    action("continue")
    after_restart = wait_for(lambda s: s.get("mode") == "battle", "재시작 뒤 이어하기")
    expect(unit_summary(after_restart) == unit_summary(saved_run), "강제 종료 뒤 ID·종류·배치 저장 복원")
    for field in ("gold", "lives", "wave", "speed"):
        expect(after_restart.get(field) == saved_run.get(field), f"강제 종료 뒤 {field} 저장 복원")
    expect(abs(float(after_restart.get("time", 0)) - float(saved_run.get("time", 0))) < 0.01,
           "강제 종료 뒤 게임 시간 저장 복원")
    (args.output / "state-process-restart.json").write_text(
        json.dumps(after_restart, ensure_ascii=False, indent=2) + "\n")
    verify_capture("process-restart-battle.png", "프로세스 재시작 뒤 전투 화면 캡처")
    crash_log = run("logcat", "-d", "-b", "crash", timeout=30)
    expect("org.projectrd.debug" not in crash_log, "앱 크래시 로그 없음")
    api = int(run("shell", "getprop", "ro.build.version.sdk"))
    release = run("shell", "getprop", "ro.build.version.release")
    environment = {"package": args.package, "android_api": api, "android_release": release}
    (args.output / "android-environment.json").write_text(
        json.dumps(environment, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps({**environment, "checks": checks, "passed": len(checks)}, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as error:
        print(f"FAIL {error}", file=sys.stderr, flush=True)
        raise SystemExit(1)
