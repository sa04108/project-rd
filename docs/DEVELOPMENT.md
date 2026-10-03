# 개발 환경과 실행 안내

엔진 버전은 [`.godot-version`](../.godot-version)의 `4.7.2-stable`입니다. 결정 대기·미완료·미검증 항목은 [남은 작업](REMAINING.md), 리소스 원본과 제작 규칙은 [리소스 안내](RESOURCE_GUIDE.md)를 참고하세요.

## 환경 준비

저장소 루트에서 실행합니다. `scripts/web-setup.sh`는 고정된 Godot Linux x86_64 실행 파일과 Web export template을 받아 SHA-512로 검증합니다. 시스템 도구나 Android SDK는 설치하지 않습니다.

Debian 13/Ubuntu 24.04의 예:

```sh
sudo apt-get update
sudo apt-get install --yes curl unzip coreutils gawk ripgrep python3
bash scripts/web-setup.sh
```

`curl`, `unzip`, `sha512sum`, `awk`는 고정 파일을 받고 확인하는 데 필요합니다. `rg`와 `timeout`은 Web export 스크립트에 사용되며, `python3`는 로컬 서버와 export 산출물 확인에 사용됩니다. Godot GUI 실행에는 해당 Linux 데스크톱의 그래픽 라이브러리가 필요합니다. 화면이 없는 Linux에서 직접 실행하려면 별도 X 서버 환경을 준비하세요.

엔진은 `.godot-tools/4.7.2-stable/godot`에, Web template과 사용자 설정·캐시는 저장소의 `artifacts/` 아래에 놓입니다. 프로젝트를 직접 열거나 명령행에서 실행할 때 아래 경로를 사용하면 사용자별 엔진 파일을 격리할 수 있습니다.

```sh
export GODOT="$PWD/.godot-tools/4.7.2-stable/godot"
export XDG_DATA_HOME="$PWD/artifacts/user-data"
export XDG_CONFIG_HOME="$PWD/artifacts/user-config"
export XDG_CACHE_HOME="$PWD/artifacts/user-cache"
mkdir -p "$XDG_DATA_HOME" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME"
```

## 가져오기와 기본 실행

프로젝트를 처음 열거나 리소스를 바꾼 뒤에는 편집기에서 가져오기가 끝날 때까지 기다린 다음 실행합니다.

```sh
"$GODOT" --editor --path .
```

편집기에서 **Project → Reload Current Project**로 변경한 리소스를 다시 읽을 수 있습니다. 프로젝트 창이 뜨면 **F6**은 현재 장면, **F5**는 기본 게임을 실행합니다. 창을 닫아 편집기로 돌아갑니다.

명령행에서 리소스를 가져오고 기본 게임을 실행하는 방법:

```sh
"$GODOT" --headless --editor --path . --import --quit
"$GODOT" --path .
```

첫 명령은 리소스 import까지만 하고 종료합니다. 두 번째 명령은 그래픽 창을 엽니다. 실제 게임 입력과 화면을 살펴볼 때는 편집기에서 F5를 사용하거나 그래픽이 연결된 세션에서 두 번째 명령을 실행하세요. 임시 데이터와 캡처는 `artifacts/`에 보관합니다.

## Web export와 로컬 실행

Web 내보내기는 고정 엔진/template을 준비하고 프로젝트를 import한 뒤 `artifacts/web/`에 빌드합니다.

```sh
bash scripts/web-export.sh
python3 scripts/web-serve.py --directory artifacts/web
```

서버는 기본으로 `http://127.0.0.1:4173/`에 바인딩합니다. 로컬 브라우저에서 열어 로딩·입력·화면 크기 변경·저장과 새로고침 뒤 이어하기를 직접 살펴봅니다. 서버를 끝내려면 터미널에서 Ctrl+C를 누릅니다. 다른 export 위치를 쓰려면 경로를 인자로 줍니다.

```sh
bash scripts/web-export.sh artifacts/web-local
python3 scripts/web-serve.py --directory artifacts/web-local --port 4180
```

`.github/workflows/web-preview.yml`은 `main` push 또는 `workflow_dispatch` 수동 실행으로 Web 빌드와 GitHub Pages 배포를 수행합니다. 자동 테스트 단계는 없습니다. 최초 공개 전 저장소 **Settings → Pages → Source**를 **GitHub Actions**로 설정하고, 배포 뒤 실제 Pages 주소를 브라우저에서 확인합니다. 로컬 export 성공만으로 공개 배포가 끝났다고 판단하지 않습니다.

## Android 내보내기와 수동 실행

Android 작업은 Linux x86_64, Java, Python 3, `curl`, `unzip`, `sha1sum`, `sha512sum`, `grep`, `rg`, Android SDK command-line tools 및 Android export template이 필요합니다. `scripts/android-setup.sh`는 Android API 35 빌드 도구와 API 30 AOSP x86_64 에뮬레이터 이미지를 `/workspace/.tools/android-sdk/`에 준비하고 Godot 템플릿을 `/workspace/.tools/godot-templates/` 아래에 둡니다. 라이선스 동의가 필요하며, 가상화가 불가하면 에뮬레이터가 느리거나 시작되지 않을 수 있습니다.

```sh
bash scripts/web-setup.sh
bash scripts/android-setup.sh
bash scripts/android-export.sh
```

디버그 APK는 `artifacts/android/project-rd-debug.apk`에 생성됩니다. 설치 후 실행은 준비된 ADB를 사용합니다.

```sh
SDK_ROOT="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-/workspace/.tools/android-sdk/sdk}}"
ADB="$SDK_ROOT/platform-tools/adb"
export ANDROID_SERIAL='DEVICE_SERIAL'
"$ADB" devices -l
"$ADB" install -r artifacts/android/project-rd-debug.apk
"$ADB" shell monkey -p com.puzzlemind.frd 1
```

전용 에뮬레이터/기기에서 해상도와 입력을 수동으로 살펴봅니다. `pm clear com.puzzlemind.frd`는 저장 데이터 전체를 삭제하므로 실행 전 필요한 진행 상태인지 확인하세요. 실기기에서는 노치·GPU·발열·백그라운드 정책도 확인해야 합니다. 에뮬레이터 실행 결과는 제조사 기기 호환성을 보증하지 않습니다.

## 로컬 확인과 테스트 코드

언어는 `data/localization.json`의 한국어 원문 키와 `en`·`zh_CN`·`ja` 번역으로 관리합니다. `game/localization.gd`가 Godot TranslationServer에 등록하며, 숫자·이름을 넣는 문장은 원문 템플릿을 먼저 번역한 뒤 포맷합니다. 저장된 정의 ID와 전투 종료 사유는 언어를 바꿔도 보존합니다. CJK 번역을 바꾸면 [폰트 제작 절차](RESOURCE_GUIDE.md#배경ui폰트)에 따라 부분집합을 다시 만들고 네 언어의 작은 화면 줄바꿈, 드롭다운, 저장 후 재시작을 확인합니다.

게임을 바꾸면 편집기나 내보낸 실행본에서 해당 동작을 직접 살펴보고, 저장·입력·화면·오디오 중 영향을 받는 경로를 실제 실행으로 확인합니다. 내보내기 전 프로젝트 리소스 import가 끝났는지, 원하는 플랫폼 preset을 선택했는지, 출력 파일이 `artifacts/`에 생성됐는지 확인합니다. 결과 캡처와 로그도 같은 디렉터리에 둡니다.

테스트 코드는 저장소에서 유지하거나 커밋하지 않습니다. 필요한 임시 검증 코드는 `/tmp/` 또는 Git에서 제외된 `artifacts/`에만 두고 로컬에서 실행한 뒤, 결과물과 함께 제거하거나 격리 상태로 남깁니다. 테스트용 fixture·runner·전용 의존성도 커밋하지 않습니다. Pages 배포 workflow에는 테스트를 추가하지 않습니다.

## 산출물

내보낸 빌드, import 결과와 사용자 데이터, 임시 로그·캡처는 `artifacts/`에 보관합니다. 엔진 캐시와 Web template은 `.godot-tools/` 또는 그 안에 지정된 사용자 데이터 경로, Android SDK와 template은 `/workspace/.tools/` 아래에 둡니다. 리소스 제작 원본·출처·라이선스는 안내된 추적 경로에 보존하고 일회성 검토 파일은 산출물 디렉터리에 둡니다.
