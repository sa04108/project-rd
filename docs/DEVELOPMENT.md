# 개발 및 검증 안내

이 문서는 저장소의 반복 가능한 개발·검증 절차를 설명합니다. 엔진은 [`.godot-version`](../.godot-version)에 고정되어 있으며, 현재 값은 `4.7.2-stable`입니다. 작업 상태와 결정 대기는 [남은 항목](REMAINING.md), 게임 리소스 제작·가져오기는 [리소스 안내](RESOURCE_GUIDE.md)를 참고하세요.

## 환경 준비와 기본 검사

저장소 루트에서 실행합니다. `scripts/web-setup.sh`는 고정된 Godot Linux x86_64 실행 파일과 Web export 템플릿을 내려받고 공식 SHA-512 목록으로 검증합니다. 이 스크립트는 OS 도구, Node.js, 브라우저 또는 Android SDK를 설치하지 않습니다.

Debian 13/Ubuntu 24.04에서 필요한 기본 도구의 설치 예입니다. 다른 Linux 배포판에서는 같은 프로그램을 해당 패키지 관리자로 준비합니다.

```sh
sudo apt-get update
sudo apt-get install --yes curl unzip coreutils gawk ripgrep xvfb xauth libgl1-mesa-dri nodejs npm
```

`curl`, `unzip`, `sha512sum`, `awk`는 버전이 고정된 엔진/템플릿 다운로드에, `rg`, `timeout`은 회귀 스크립트에 필요합니다. `xvfb`, `xauth`, Mesa 소프트웨어 렌더러는 화면 검사용이고, Node.js/npm은 Playwright 브라우저 검사에 사용합니다. Android 검사는 뒤에 적힌 SDK 별도 준비 절차가 필요합니다.

```sh
bash scripts/web-setup.sh
```

스크립트는 엔진을 `.godot-tools/4.7.2-stable/`에, 사용자 데이터와 Web export 템플릿을 `artifacts/user-data/` 아래에 둡니다. 이 저장소에서 Godot 명령을 직접 실행할 때는 다음 공통 환경을 사용합니다.

```sh
export GODOT="$PWD/.godot-tools/4.7.2-stable/godot"
export XDG_DATA_HOME="$PWD/artifacts/user-data"
export XDG_CONFIG_HOME="$PWD/artifacts/user-config"
export XDG_CACHE_HOME="$PWD/artifacts/user-cache"
mkdir -p "$XDG_DATA_HOME" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME"
```

`scripts/verify.sh`, `scripts/mvp-check.sh`, `scripts/web-export.sh`는 다른 동일 버전 실행 파일을 `GODOT_BIN=/path/to/godot`으로 지정할 수 있습니다. Android export는 이 변수를 사용하지 않고 `.godot-tools/4.7.2-stable/godot` 경로를 요구합니다. `scripts/web-setup.sh`는 저장소의 고정 버전 및 x86_64를 요구합니다.

기본 회귀 검사는 import, 규칙·저장·아트·애니메이션 계약, 생명주기, 오디오, 드래그 포인터, HUD, 전투 효과와 실행 smoke를 포함합니다.

```sh
bash scripts/verify.sh
```

화면 입력과 배치까지 확인할 때는 Xvfb와 소프트웨어 렌더링을 사용하는 시각 검사를 추가합니다.

```sh
VERIFY_VISUAL=1 bash scripts/verify.sh
```

`verify.sh`는 `mvp-check.sh`에 검사를 위임합니다. 상세 단계별 로그는 `artifacts/logs/`에 저장됩니다. 직접 실행할 때 `bash scripts/mvp-check.sh`는 import와 계약, 생명주기, 오디오, 정체성 애니메이션 검사를 포함하고 `VERIFY_VISUAL=1`이면 네이티브 UI 시나리오도 실행합니다. 스크립트는 격리된 Godot 사용자 경로를 `artifacts/` 아래에 사용합니다.

## 변경 유형별 권장 검사

| 변경 | 검사 |
| --- | --- |
| 규칙, 저장 형식, 카탈로그 | `bash scripts/verify.sh` (규칙 및 저장 계약 포함) |
| UI, 입력, 배치, 장면 전환 | `VERIFY_VISUAL=1 bash scripts/verify.sh` |
| 전투 애니메이션 연결·상태 | 기본 검사 후 시각 검사. 캡처가 필요하면 아래 애니메이션 절차 실행 |
| 리소스 생성·가져오기 | [리소스 안내](RESOURCE_GUIDE.md)의 해당 리소스 검사와 `VERIFY_VISUAL=1 bash scripts/verify.sh` |
| 밸런스 가설 | 시드 범위를 기록한 봇 표본 실행; 사람 대상 결과로 해석하지 않음 |
| 오디오 라우팅·설정 | 기본 검사에 포함된 오디오 회귀 검사; 브라우저·기기에서 실제 청감 확인은 별도 |
| Web 저장, 새로고침 복원 | 로컬 Web export와 Playwright 브라우저 QA |
| Android 입력·수명주기·저장 | 디버그 APK export 후 에뮬레이터 검사; 실기기는 별도 명시 |
| 문서, 링크, 명령 예시 변경 | 링크·참조 경로와 스크립트 옵션을 대조하고 shell 구문 및 `git diff --check` 확인; 실행 스크립트나 설정 자체를 바꿨다면 해당 명령 실행 |

UI·지형 변경에서는 폭 1칸/중심선 28단위의 정투영 길과 26→28 저장 진행도 보정, 드래그 전용 이동·격자·노란 안내, 가려진 UI 위 드롭 취소, 상단 도구 순서와 하단 버튼 위치, 입력을 막지 않는 최상단 안내를 함께 확인합니다. 메뉴 제목은 `presentation/display_name`만 바꾸고 저장·패키지 식별자는 유지하는지, 홈 버튼의 저장 실패가 전투 화면을 보존하는지 검사합니다. 글꼴·제목을 바꾼 뒤에는 최종 리소스를 다시 가져와 작은 화면·Web의 글자 폭, 잘림, fallback과 패널 없는 제목을 캡처로 확인합니다.

검사가 실패하면 `artifacts/logs/`의 해당 로그를 확인합니다. 자동 테스트 통과는 사람 플레이 밸런스, 아트 품질, 기기별 호환성 또는 실제 청감의 승인을 대신하지 않습니다.

## 전투 애니메이션 확인

일반 회귀 검사는 애니메이션 계약과 표시 경로를 검사합니다. 실제 공격·준비·회복 포즈를 렌더링해 캡처하려면 Linux에서 Xvfb와 소프트웨어 GL을 사용합니다.

```sh
timeout --kill-after=5s 90s xvfb-run -a -s '-screen 0 900x1400x24' \
  env LIBGL_ALWAYS_SOFTWARE=1 "$GODOT" \
  --path . --audio-driver Dummy --rendering-method gl_compatibility \
  --resolution 720x1280 --script res://tests/animation_capture.gd -- --ui-test
```

`tests/identity_visual_scenario.gd`는 모든 정체성 애니메이션 프레임을 렌더링하는 별도 시각 시나리오입니다. 보고서와 캡처는 `artifacts/identity-visual/`에 저장합니다.

```sh
timeout --kill-after=5s 180s xvfb-run -a -s '-screen 0 900x1400x24' \
  env LIBGL_ALWAYS_SOFTWARE=1 "$GODOT" \
  --path . --audio-driver Dummy --rendering-method gl_compatibility \
  --resolution 720x1280 --script res://tests/identity_visual_scenario.gd
```

두 명령은 앞의 공통 환경과 `xvfb-run`, `Xvfb`, `xauth`, Mesa 소프트웨어 GL이 필요합니다. 정체성 시나리오는 실제 display가 필요하며 Godot headless에서는 의도적으로 실패합니다. 캡처를 직접 열어 프레임 잘림·장비·몸 크기·상태 전환을 확인합니다. 로그도 확인하며, 렌더링 캡처만으로 전투 규칙 불변성 검사를 대신하지 않습니다.

아군 무기/지원 오라와 적 재질·피격/제거 효과의 전체 갤러리는 같은 표시 환경에서 별도로 렌더링할 수 있습니다. 저장 경로를 먼저 만들고 기본 효과 계약 검사와 함께 실행합니다.

```sh
mkdir -p artifacts/screenshots
timeout --kill-after=5s 90s xvfb-run -a -s '-screen 0 1400x1600x24' \
  env LIBGL_ALWAYS_SOFTWARE=1 "$GODOT" \
  --path . --audio-driver Dummy --rendering-method gl_compatibility \
  --script res://tests/effects_contract_test.gd -- --effects-gallery
```

`artifacts/screenshots/effects-allies.png`와 `effects-enemies.png`를 직접 확인합니다. 현재 인덱스 기준 아군 공격·대기 각 34행과 적 이동 53행을 모두 순회하고, 효과는 아군 34종·적 53종·지원 오라 6종이 누락되지 않는지 확인합니다. 결과 수치·캡처 목록은 실행 산출물에서 확인하고 안내서에 완료 로그를 누적하지 않습니다.

패킹·이미지 최적화 도구 변경은 다음 Python 검사를 추가합니다. 상세 픽셀·백업·영수증 계약은 [리소스 안내](RESOURCE_GUIDE.md)를 따릅니다.

```sh
python3 -B -m unittest discover -s tools/art -p 'test_*.py'
```

## 밸런스 봇 표본

입문자 대리 정책으로 시드 구간을 실행할 수 있습니다. 표본 크기는 최대 200입니다.

```sh
"$GODOT" --headless --path . \
  --script res://tests/novice_playthrough.gd -- \
  --seed-start=1 --sample-count=80
```

결과는 `artifacts/balance/`에 기록됩니다. 봇의 행동 정책과 결과는 자동화된 비교용이며 실제 이용자 첫 플레이 관측값으로 보고하지 않습니다. 시드 범위와 표본 수를 비교할 때는 두 실행에서 정책과 콘텐츠 버전을 함께 기록하세요.

별도의 5개 시드 전략 봇 검사는 각 시드를 게임 종료 또는 3,600 게임 초까지 진행하고 불변식을 확인합니다(최대 100웨이브).

```sh
"$GODOT" --headless --path . \
  --script res://tests/balance_playthrough.gd
```

성공 시 `BALANCE_INVARIANTS_PASS`를 출력합니다. 이 테스트는 결과 파일을 저장하지 않으며 실제 사람의 플레이 밸런스를 측정하지 않습니다.

## 오디오 검사

`bash scripts/verify.sh`는 `tests/audio_regression.gd`를 실행하여 설정, 라우팅, 샘플 형식, 무음 꼬리 및 UI/전투 재생 조건을 점검합니다. 개별 실행은 다음과 같습니다.

```sh
"$GODOT" --headless --path . \
  --script res://tests/audio_regression.gd -- --ui-test
```

음소거·볼륨·루프·동시 재생과 샘플의 실제 인상은 대상 브라우저나 기기에서 별도로 들어 확인합니다. 자동 검사는 청감이나 장시간 플레이를 보증하지 않습니다.

## Web 내보내기와 브라우저 검사

고정 엔진과 Web 템플릿을 준비한 뒤 내보내고 로컬 HTTP 서버로 제공합니다.

```sh
bash scripts/web-setup.sh
bash scripts/web-export.sh
python3 scripts/web-serve.py --directory artifacts/web
```

서버 기본 주소는 `http://127.0.0.1:4173/`입니다. 별도 터미널에서 브라우저 자동 검사를 준비하고 실행합니다.

```sh
npm ci --prefix tools/web
tools/web/node_modules/.bin/playwright install --with-deps chromium
CHROMIUM_PATH="$(node -e 'process.stdout.write(require("./tools/web/node_modules/playwright").chromium.executablePath())')" \
  node tools/web/browser-qa.cjs \
  --base-url 'http://127.0.0.1:4173/' --output artifacts/web-qa
```

워크플로와 같이 Playwright가 설치한 Chromium을 명시적으로 선택합니다. `CHROMIUM_PATH`를 생략하면 `/usr/bin/chromium`이 있을 때 이를 우선 사용합니다.

검사는 QA 브리지를 `?qa=1` 주소에서만 사용하며 실제 캔버스 입력, 화면 크기 변화, 저장·이어하기, 새로고침 복원을 검사합니다. 저장 검증은 브라우저의 IndexedDB에 저장된 QA `run.json` 및 `profile.json`을 읽기 전용으로 확인하고, 기대한 전체 스냅샷이 기록될 때까지 최대 20초 기다린 뒤 새로고침 복원값과 비교합니다. 파일 존재만으로 저장 완료라 판단하거나 동기화를 강제하지 않습니다. 이 자동 절차는 저장 직후 탭을 닫아도 데이터가 보존된다는 보장을 하지 않습니다.

수동 배포 검증은 `.github/workflows/web-preview.yml`의 `workflow_dispatch`에서만 시작합니다. 현재 push trigger는 주석 처리되어 있습니다. 선택한 ref의 빌드와 브라우저 검사가 성공하면 그 실행 산출물을 GitHub Pages에 배포합니다. 최초 배포 전 저장소 **Settings → Pages → Source**를 **GitHub Actions**로 설정해야 합니다. 로컬 검사나 Actions 검사만으로 공개 URL이 정상임을 주장하지 말고 실제 URL을 확인합니다.

## Android 디버그 검사 (선택)

Android 검사는 릴리스 패키지나 스토어 배포가 아니라 내부 디버그 APK를 대상으로 합니다. Linux x86_64, Java, Python 3, `curl`, `unzip`, Android SDK command-line tools 및 에뮬레이터가 필요합니다. 가상화가 가능하면 KVM을 사용하며, 없으면 TCG가 느리거나 시작되지 않을 수 있습니다.

고정 엔진이 준비되어 있는 상태에서 SDK, API 30 기본 AOSP x86_64 이미지 및 Godot 4.7.2 Android 템플릿을 준비하고 APK를 내보냅니다.

```sh
bash scripts/web-setup.sh
bash scripts/android-setup.sh
bash scripts/android-export.sh
```

다음 명령은 기본 AVD를 시작하고 APK를 설치한 뒤 자동 입력·화면·수명주기·재실행 검사를 수행합니다. 이 스크립트는 들어온 `ANDROID_SERIAL` 값을 사용하지 않고 자체 AVD를 `emulator-5554`로 실행합니다. 이미 같은 serial로 연결된 디바이스가 있으면 실행을 거부하므로, 이 명령은 에뮬레이터 QA에만 사용합니다.

기본 `host` GPU 경로는 `.godot-tools/os/usr/bin/xvfb-run`을 직접 사용합니다. 이 클라우드 경로가 없는 새 환경에서는 앞서 설치한 시스템 Xvfb 실행기로 연결합니다. `setsid`도 필요합니다(Debian/Ubuntu의 `util-linux`).

```sh
if [ ! -x .godot-tools/os/usr/bin/xvfb-run ]; then
  mkdir -p .godot-tools/os/usr/bin
  ln -s "$(command -v xvfb-run)" .godot-tools/os/usr/bin/xvfb-run
fi
bash scripts/android-emulator-test.sh
```

기본 검사는 에뮬레이터의 `org.projectrd.debug` 앱 데이터를 지우고 새 실행 상태로 시작합니다. 검사용 저장 파일이 지워져도 되는지 확인한 뒤 실행하세요. APK, 로그, 캡처는 각각 `artifacts/android/`, `artifacts/logs/android-qa/`, `artifacts/screenshots/android/` 아래에 둡니다. API 및 GPU 환경은 실제 실행 manifest에 기록됩니다.

전용 실기기에서 검증할 때는 먼저 APK를 설치하고 앱 데이터 초기화가 필요한지 확인합니다. 아래 `pm clear` 명령은 앱의 저장 데이터를 지우므로 주석 처리한 채 필요할 때만 실행하세요. `ANDROID_SDK_ROOT` 또는 `ANDROID_HOME`이 있으면 그 값을 adb 경로에 사용하고, 둘 다 없으면 저장소 스크립트의 기본 SDK 위치를 사용합니다. 자동화 입력 좌표는 720×1280 화면을 기준으로 하므로 다른 해상도에서는 좌표를 조정하기 전 결과를 통과로 취급하지 않습니다.

```sh
SDK_ROOT="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-/workspace/.tools/android-sdk/sdk}}"
ADB="$SDK_ROOT/platform-tools/adb"
export ANDROID_SERIAL='DEVICE_SERIAL'
"$ADB" devices -l
"$ADB" install -r artifacts/android/project-rd-debug.apk
# 저장 초기화가 필요한 전용 기기에서만 주석을 풀어 실행합니다.
# "$ADB" shell pm clear org.projectrd.debug
"$ADB" shell monkey -p org.projectrd.debug 1
python3 tools/android/qa_driver.py \
  --adb "$ADB" --package org.projectrd.debug \
  --output artifacts/logs/android-qa/device \
  --screenshots artifacts/screenshots/android/device
```

에뮬레이터 통과는 실제 제조사 기기의 GPU, 노치, 발열, 해상도, 백그라운드 정책 호환성을 보증하지 않습니다.

## 산출물과 재현성

생성된 빌드, 브라우저 결과, 스크린샷, 테스트 로그는 `artifacts/` 아래에 둡니다. 엔진·SDK 다운로드 캐시와 export 템플릿은 스크립트가 지정한 `.godot-tools/` 또는 `/workspace/.tools/` 경로에 저장됩니다. 제출 전에 저장소의 상태를 확인하고, 이 로컬 산출물을 소스 변경과 혼동하지 마세요.
