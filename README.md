# project-rd · 용병 길드

Godot 4.4.1, GDScript, 세로 720×1280의 오프라인 타워 디펜스 MVP입니다.
소환 → 조합 → 재배치 → 성급 강화와 군중제어 → 100웨이브 마왕 처치까지 플레이할 수 있습니다.

## 실행

Godot **4.4.1 standard**로 `project.godot`을 열어 실행하거나:

```bash
/path/to/godot-4.4.1 --path .
# 이 클라우드 환경에서는:
.godot-tools/4.4.1-stable/godot --path .
```

클라우드에서 화면을 검증할 때는 Xvfb를 사용합니다. 사용자에게 노출되는 로컬 웹 미리보기는 제공하지 않습니다.

## 조작

- 큰 **소환** 버튼으로 1성 영입. 시작 골드는 세 번의 소환 비용입니다.
- 용병을 누른 뒤 목적지 칸을 누르거나 드래그합니다. 점유 칸은 서로 교환합니다.
- 선택한 용병을 다시 누르면 선택을 해제합니다. **조합법**에서 재료·결과 칸을 확인한 뒤 조합합니다.
- 배속 버튼은 **×1 → ×2 → ×3 → ×5**, 일시정지는 별도 버튼입니다.
- **설정**만 전투를 자동 정지합니다. 도감·조합법·하단 창을 열어도 전투는 진행됩니다.
- 특수몬스터는 보상을 주는 **적**입니다. 10·30·60웨이브 완료 후 종류별로 해금됩니다.
- 설정의 **저장 후 메인 메뉴**와 메인의 **이어하기**를 사용합니다. 복원 후 **재개**를 눌러야 시간이 흐릅니다.

## 제공 범위

- 6×6 배치, 외곽 26단위 단방향 경로, 100웨이브 전체 일정과 마왕 승패.
- 34종 용병(1/2/3/4성 각 6/10/12/6), 28개 조합법.
- 일반 적 40종, 보스 9종과 마왕 1종, 보상형 특수몬스터 3종.
- 공유 공격력 강화, 성급별 도박, 둔화·기절·범위 공격·화력 지원.
- 도감, 설정, 최고 도달/클리어 분리 기록, 원자적 저장과 손상 파일 격리.
- 생성 배경, 87종 개별 원화, sprite-gen 프롬프트/추출 기반 7계열 애니메이션 파이프라인. 계열별 실제 제작 범위는 [아트 기록](docs/ART_PIPELINE.md)에 구분합니다.
- 일반·보스·특수를 합친 전장 적 수가 50마리에 도달하면 즉시 패배합니다. 한도는 T 데이터에서 조정합니다.

## 검증

```bash
bash scripts/mvp-check.sh
VERIFY_VISUAL=1 bash scripts/mvp-check.sh
GODOT_BIN=/path/to/godot-4.4.1 bash scripts/mvp-check.sh
.godot-tools/4.4.1-stable/godot --headless --path . --script res://tests/balance_playthrough.gd
```

`mvp-check.sh`는 버전, import, 29개 규칙·저장·아트 검사, 메인 300회 반복을 확인합니다.
화면 검증을 켜면 Xvfb와 Mesa로 실제 UI 입력 104개 검사를 수행하고 `artifacts/screenshots/`에 PNG를 만듭니다.
로그와 테스트용 저장 데이터는 `artifacts/`에 격리합니다.

개발용 웨이브 점프는 `-- --dev`로 실행한 경우에만 F8로 제공합니다. 개발 판은 최고 기록에 반영되지 않습니다.
`--capture-battle`은 시각 검사용 구성이고 정상 플레이/밸런스 결과와 구분합니다.

Android 내부 디버그 테스트는 아래 순서로 재현합니다. 출시용 패키지·스토어 배포는 범위 밖입니다.

```bash
bash scripts/android-setup.sh
bash scripts/android-export.sh
bash scripts/android-emulator-test.sh
```

이 클라우드의 기본 구성은 API 30 AOSP + Xvfb/Mesa llvmpipe이며, 실제 APK에서 화면·입력·저장 복원 등 44개 검사를 통과했습니다. 상세 결과와 물리 기기 연결 방법은 [Android QA](docs/ANDROID_QA.md)를 확인하세요.
첫 클리어율 5%는 사람 대상 목표이며 자동 플레이 봇의 성공률과 동일한 수치가 아닙니다.

[실제 검증 결과](docs/QA_ACCEPTANCE.md) · [구현 결정](DECISIONS.md) · [미구현·결정 사항](docs/REMAINING.md) · [명세](docs/MVP_SPEC_v0.2.md)
