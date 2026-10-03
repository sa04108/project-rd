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

### 물리 선택과 Web 메모리

현재 전투·배치 판정은 자체 시뮬레이션과 `Control` 입력을 사용하므로 `physics/common/enable_object_picking=false`를 유지합니다. 충돌체 선택으로 불필요한 `World2D` 물리 공간이 활성화되는 것을 막으며, Godot 4.7.2 단일 스레드 Web의 완료된 물리 작업 그룹 누적 경로도 피합니다. 일반 GUI 클릭·터치·드래그는 별도 입력 경로입니다.

향후 `CollisionObject2D`의 입력·호버 기능을 도입한다면 이 설정의 의존성과 엔진의 작업 그룹 해제를 먼저 확인합니다. 메모리는 포인터 입력 뒤 전투/메뉴를 반복하고 같은 장면이 정착한 시점끼리 비교합니다. 엔진의 live static allocation, 노드·리소스·오디오 재생 수와 브라우저/Wasm 예약 용량은 구분해서 관찰합니다. 진단 코드와 결과는 로컬 `artifacts/`에만 둡니다.

### WebGL 핸들 테이블 후처리

`scripts/web-export.sh`는 export 뒤 `web-patch-gl-tables.py`로 생성된 `index.js`의 GL 핸들 테이블만 후처리합니다. 공식 4.7.2 단일 스레드·확장 미사용 **release와 debug** 템플릿의 ZIP·원본 JS·변환 결과 SHA-256을 고정하며, 전역 ID 순서와 `0=null`은 유지합니다. 해제된 핸들의 빈 배열 슬롯이 계속 쌓이지 않도록 숫자 키 사전을 사용하고 해제된 키를 삭제합니다. 이는 엔진 live static allocation과 별개인 [Emscripten의 GL 테이블 증가 문제](https://github.com/emscripten-core/emscripten/issues/21921)를 처리합니다.

원본 JS의 저작권·라이선스 표기는 보존하며, Wasm·템플릿 ZIP·게임 리소스는 수정하지 않습니다. 완성된 결과를 같은 디렉터리의 임시 파일에서 원자적으로 교체하고, 이미 검증된 결과에 재실행하면 쓰기 없이 종료합니다. 버전·템플릿·JS 해시가 다르거나 수정 위치가 예상과 다르면 **내보내기를 실패 처리**합니다. 엔진 업그레이드, 스레드·확장 또는 custom template 변경 시에는 해당 런타임의 모든 테이블 사용처와 실제 렌더링·입력을 다시 확인한 뒤 지원 해시를 갱신해야 하며, 검사를 건너뛰지 않습니다.

이 단계는 Python 표준 라이브러리만 쓰는 빌드 변환입니다. 브라우저·메모리·입력 검증과 그 의존성은 로컬 `artifacts/`에만 두며 배포 workflow에 테스트 단계를 추가하지 않습니다. debug export도 `WEB_EXPORT_MODE=debug bash scripts/web-export.sh artifacts/web-debug`로 같은 보호 절차를 거칩니다.

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

언어는 `data/localization.json`의 의미 기반 고정 키로 관리합니다. 예를 들어 `settings.language` 아래에 `en`·`ko`·`zh_CN`·`ja` 값을 모두 두며 한국어 문장을 키로 쓰지 않습니다. 용병은 `unit.u01.name`·`unit.u01.description`, 적은 `enemy.n01.name`처럼 기존 정의 ID를 사용하므로 이름이나 설명을 수정해도 키는 유지합니다. 문구를 추가할 때 네 언어 값과 포맷 인자의 종류·순서를 맞춥니다.

`game/localization.gd`가 Godot TranslationServer에 등록하며, 호출부는 `L.text("settings.language")`처럼 키를 명시합니다. 숫자·이름을 넣는 문장은 템플릿을 먼저 번역한 뒤 포맷하고, Label·Button·알림의 표시 함수에 완성된 문장을 전달합니다. 재화 아이콘의 `{diamond}` 자리는 `CurrencyLabel`에서 텍스처로 바꾸며 번역에 BBCode나 이미지 경로를 넣지 않습니다. 해당 문구를 일반 Label에 연결하지 않고, 접근성 이름에는 번역된 재화 명칭이 남는지 확인합니다. 저장 오류는 고정 키로 표시 계층에 전달하고, 새 전투 종료 사유도 고정 키로 저장합니다. 이전 저장의 한국어 종료 사유는 호환 처리로 읽습니다. CJK 번역을 바꾸면 [폰트 제작 절차](RESOURCE_GUIDE.md)에 따라 부분집합을 다시 만들고 네 언어의 작은 화면 줄바꿈, 드롭다운, 저장 후 재시작을 확인합니다.

도감·조합법 용병 목록의 `CatalogFilters`는 성급, 거리, 대상 수, 행동 필터를 AND로 적용합니다. 표시 분류와 필터는 `UnitDescription`의 같은 순수 판정 함수를 사용합니다. 새 필터 상태 라벨은 `catalog.filter.distance`, `catalog.filter.targets`, `catalog.filter.action`의 네 언어 값을 등록합니다. 공격력 증가 버프 용병은 공격·지원 필터에 모두 포함하고, 둔화·기절은 별도 능력 설명으로 표시합니다.

레시피 추적은 프로필 스키마 3의 `preferences.recipe_tracking.unit_ids`에 조합 결과 용병 ID와 추적 순서를 저장합니다. 프로필 스키마 1은 빈 추적 목록을, 스키마 1·2는 로컬 경제 초기값을 더해 스키마 3으로 마이그레이션합니다. 추적 목록 타입·중복·ID를 엄격히 검증하고 삭제된 레시피 결과 ID만 제거해 나머지 프로필 데이터를 보존합니다. 더 높은 숫자 스키마는 읽기 전용으로 열어 덮어쓰지 않습니다.

다이아몬드·영구 단계는 프로필 스키마 3의 `economy`에 저장되는 로컬 진행 시스템입니다. `data/permanent_progression.json`이 시작 잔액·보상·업그레이드 가격·상한·효과의 단일 원본이며, 저장소 API는 예상 단계와 원장 revision을 비교한 뒤 구매 차감·단계 변경·원장 기록을 프로필에 함께 저장합니다. run 종료의 보상·기록도 같은 프로필 갱신에 포함하고 milestone/run 식별자로 재저장 중 중복 지급을 막습니다. 진행 중 스냅샷은 새 전투 시작 시 고정된 영구 단계와 준비 시간·사용자 정지를 보존하므로, 이어하기에 나중 구매를 섞지 않습니다. 이 로컬 지갑은 변조 방지나 유료 재화의 신뢰 가능한 권위 저장소가 아닙니다. 실제 구매·소셜 계정은 서버 권위 지갑·원장, 영수증 검증, 멱등 거래 및 계정 연결 정책을 결정한 뒤 구현하며 [REMAINING](REMAINING.md)의 D03에서 관리합니다.

경제 원장의 과거 차감·지급 금액은 거래 당시 확정값입니다. 현재 튜닝 가격으로 과거 원장을 다시 계산하지 않으며, 저장된 금액으로 잔액·누적 수입·지출·단계를 재구성해 일관성을 검사합니다. 신규 거래는 현재 데이터의 가격·해금·단계와 기대 revision을 검증한 뒤 실행합니다. 로컬 파일을 의도적으로 함께 수정하는 행위를 인증할 수 있는 구조는 아니므로 유료 구매를 활성화할 때 서버 검증으로 교체해야 합니다.

전투 스냅샷 스키마 2는 남은 준비 초, `permanent_levels`, `user_paused`를 검증해 보존합니다. 스키마 1에는 이 값들이 없으므로 기존 판을 준비 없이 시작하고 영구 보너스를 0으로 적용하며 사용자 수동 정지를 복원하지 않습니다. 스냅샷에 미래 스키마가 추가되면 현재 유효 상태로 추측해 바꾸지 말고 검증기와 마이그레이션을 함께 갱신합니다.

영구 성장 변경을 확인할 때는 새 프로필의 시작 잔액, 최초 최고 웨이브 milestone 보상, 보스 처치와 승리 보상, 같은 run 저장 반복 시 중복 지급 방지, 잔액 부족·해금 웨이브·최대 단계·읽기 전용 구매 차단을 함께 검사합니다. 저장 원자성은 구매 전후 wallet/upgrade/ledger/revision과 실패 시 원본 보존으로 확인합니다. 이어하기는 저장 당시 단계·사용자 정지를 유지하고 새 판만 최신 구매를 받는지 확인합니다.

수동 화면 확인은 720×1280에서 조합법·Records 팝업의 `(35,128,650,1024)` 경계와 대칭 여백, 투명 여백이 잘린 160×180 초상, 모든 필터 조합의 AND 동작을 살펴봅니다. 준비 레시피는 5개 제한, 성급 내림차순과 같은 성급 안의 추적 순서, 해제 후 재추적 시 끝에 추가되는 순서를 확인합니다. 조합 직전 재료가 바뀐 경우 새 상태를 검증하고, 조합·새 판·재시작 뒤 추적 설정이 유지되는지도 확인합니다. 영구 성장 창은 메뉴에서만 열리며 잔액, 현재/다음 효과, 비용, 추가 목숨의 60·100웨이브 잠금, 읽기 전용 비활성 상태와 다음 새 전투 적용 안내를 검사합니다. 새 전투의 5초 준비 시간에는 적 생성·전투 시간이 없어야 하고, 이어하기는 남은 준비 시간과 사용자 정지를 보존해야 합니다. 단순 클릭·버튼 콜백·용병 선택·드래그·취소 입력이 선택 상태 규칙을 지키는지 함께 봅니다.

용병 판매는 1·2·3성에서 각각 소환 비용의 0.5·1·2배만 골드로 반환하고 4성은 금지하며 동일 ID의 재실행으로 추가 지급되지 않아야 합니다. 준비 시간에는 허용하고 수동 정지·전투 종료 상태에서는 금지합니다. 320×568·360×640 화면과 네 언어에서 판매 버튼이 격자 아래 가운데에 놓이고 정보 태그와 인접하는지, 이름·능력치·공격 타입이 패널 안에 들어오는지, 위아래 용병의 그림자가 별표를 가리지 않는지 캡처로 확인합니다.

게임을 바꾸면 편집기나 내보낸 실행본에서 해당 동작을 직접 살펴보고, 저장·입력·화면·오디오 중 영향을 받는 경로를 실제 실행으로 확인합니다. 내보내기 전 프로젝트 리소스 import가 끝났는지, 원하는 플랫폼 preset을 선택했는지, 출력 파일이 `artifacts/`에 생성됐는지 확인합니다. 결과 캡처와 로그도 같은 디렉터리에 둡니다.

테스트 코드는 저장소에서 유지하거나 커밋하지 않습니다. 필요한 임시 검증 코드는 `/tmp/` 또는 Git에서 제외된 `artifacts/`에만 두고 로컬에서 실행한 뒤, 결과물과 함께 제거하거나 격리 상태로 남깁니다. 테스트용 fixture·runner·전용 의존성도 커밋하지 않습니다. Pages 배포 workflow에는 테스트를 추가하지 않습니다.

## 산출물

내보낸 빌드, import 결과와 사용자 데이터, 임시 로그·캡처는 `artifacts/`에 보관합니다. 엔진 캐시와 Web template은 `.godot-tools/` 또는 그 안에 지정된 사용자 데이터 경로, Android SDK와 template은 `/workspace/.tools/` 아래에 둡니다. 리소스 제작 원본·출처·라이선스는 안내된 추적 경로에 보존하고 일회성 검토 파일은 산출물 디렉터리에 둡니다.

## 출시 기능과 로컬 저장 보호

개발 웨이브 점프는 실제 debug 빌드에서만 허용한다. UI의 `--dev`와 F8 처리, 시뮬레이션의 직접 점프 호출을 모두 검사한다. Web 배포는 기존 release 기본값을 유지하며 Android Debug preset에는 사용하지 않는 QA 시작 인자를 넣지 않는다. 현재 Android 명령은 이름대로 디버그 APK를 만드는 개발 절차이며 스토어 출시본이 아니다. 정식 서명 키를 저장소에 추가하지 않는다.

저장 입력은 파싱 전에 파일당 16 MiB와 중첩 깊이 32를 확인한다. 파싱 후에는 컬렉션당 100,000개, 전체 값 250,000개, 문자열 4,096자, 유한 숫자의 절댓값 2^53−1 범위를 확인한다. 출력에도 같은 구조·크기 제한을 적용하므로 다시 읽을 수 없는 새 파일로 교체하지 않는다. 정상적인 누적 기록도 한도에 도달하면 원본을 보존하고 저장 실패를 알린다. 제한을 맞추기 위해 구매 원장이나 보상 기록을 자동으로 버리지 않는다.

프로필과 전투 파일은 처음 관측한 실제 바이트의 SHA-256과 쓰기 직전 상태를 비교한다. 다른 인스턴스의 변경이 보이면 오래된 메모리를 덮어쓰지 않고 읽기 전용으로 전환한다. 전투 저장은 프로필 반영 전에 두 파일을 확인하며 전투 파일 교체·삭제 전에도 다시 검사한다. 이는 동일 파일시스템에서 순차적으로 발생하는 오래된 쓰기를 막는 낙관적 검사다. 프로세스 간 원자적 compare-and-swap이나 서로 다른 Web 탭의 IDBFS 동기화를 보장하지 않는다.

지원하지 않는 미래 schema의 프로필·전투와 한도를 넘는 파일은 격리·초기화하지 않는다. 손상 프로필은 원본과 내용 해시 이름의 복구 사본을 보존하고 읽기 전용으로 연다. 프로필이 없지만 이전 복구 파일이 남은 경우도 신규 설치로 처리하지 않는다. 읽기 전용 상태에서는 새 전투·이어하기·구매를 차단하며 이미 열린 전투에서 충돌이 발견되면 실패 안내를 남기고 메뉴·종료로 이동할 수 있다. 이 이동은 미저장 진행의 저장 성공을 뜻하지 않는다.

이 검사는 손상과 일부 오래된 쓰기를 줄이는 로컬 무결성 보호다. 자기 저장·메모리·실행 파일을 모두 바꿀 수 있는 사용자를 인증하지 못하며, 유료 잔액·소유권·스토어 영수증의 서버 검증을 대체하지 않는다. IndexedDB의 비동기 확정, 실제 다중 탭·기기 동시성, 계정 단위 최초 지급은 별도 검증·구현이 필요하다.

### Web 저장 완료와 오류 표시

`SaveStore`의 파일 교체 성공은 Web의 IndexedDB 확정과 구분한다. `WebSavePersistence`는 로컬 교체·삭제마다 세대를 올리고, 고정 Godot 런타임의 기존 `FS.syncfs` 완료 콜백으로 그 시점의 세대만 확정한다. 이전 flush가 완료되어도 이후 쓰기가 있으면 저장 중 상태를 유지한다. 별도의 병렬 `syncfs`를 만들지 않으며 실패는 기존 엔진 경로로 최소 2초 간격 재요청한다. 동기 예외도 엔진의 오류 콜백으로 한 번 전달해 syncing 상태가 고착되지 않게 한다.

메뉴에서는 미확정 저장을 즉시, 전투에서는 1초 넘게 걸리는 저장을 화면 최상단의 작은 반투명 줄로 표시한다. 저장 실패와 영속 저장소 사용 불가는 계속 표시하며 실제 완료를 확인한 뒤에만 없앤다. 전투의 목숨·버튼 내용을 가리지 않고 입력을 통과시킨다. 미확정·실패 중에는 `beforeunload` 경고를 요청하지만 브라우저가 경고를 표시하지 않거나 사용자가 떠나기를 선택할 수 있다. 앱 강제 종료, 전원 차단, 저장소 삭제/퇴거, 다른 탭의 동시 쓰기까지 보장하지 않는다. 완료 표시의 의미는 현재 탭에서 IndexedDB 확정 콜백을 관측했다는 것이다.

관측기는 런타임당 하나만 설치하고 게임 저장 내용을 JavaScript로 복제하지 않는다. 메뉴나 `SaveStore`를 재생성해도 중첩 설치하지 않으며 정상 엔진 종료는 최종 flush 이후 `Module.onExit`에서 소유한 후크·이탈 경고만 정리한다. 엔진을 바꾸면 해당 순서와 함수 계약을 다시 검증한다. 로컬 검증에는 완료 후 종료·복원, 지연 중 이전 세대 완료, 오류/재시도/회복, 이탈 경고 취소, 화면 안내와 일반 플레이를 포함한다.
