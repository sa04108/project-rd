# 전투 표현 보강 인계

기준 main: `362401454a6dd995691f654c4a664b34a6e7cef5`.
작업 브랜치: `feat/combat-animation-polish`. 기존 `10dc930` 인계 브랜치는 변경하지 않았다.
Godot **4.7.2.stable.official.ed1daf0bf**, Compatibility, Xvfb/Mesa와 Chromium으로 검증한다.

## 구현 범위와 표현 한계

- 실제 피해 처리 직후 `attack_presented` 신호로 공격자/종류/목표/좌표/게임시간을 표시 계층에 전달한다.
  전투 시간·피해·CC·쿨타임·RNG·목표 선택·저장 스키마를 변경하지 않는다.
- `combat_visuals.gd`는 원화 자세와 베기/찌르기/타격/내려치기/활/총/투창/투척/시전/브레스 효과를
  명시적 ID 표로 구분한다. 용병34종의 기존 개별 텍스처를 유지한다.
- 연속 공격의 쿨타임 마지막0.18게임초에 유효 목표가 있으면 준비 자세를 취한다.
  공격 이벤트부터 공격 자세, 이후0.48초까지 회복한다. 최초 즉시 공격은 준비 때문에 지연시키지 않는다.
- 칼 궤적, 창 잔상, 화살/탄환/투척 궤도, 시전 문양/구체, 명중 파편을 그린다.
  판정은 기존 즉시 피해 그대로다. 명중 표시는 이벤트 즉시 시작하고 발사체 이동은 장식이다.
- 게임시간만 사용하므로 정지/설정/백그라운드/배속을 따른다. reduced-motion에서는 원화 자세 변화,
  이동 궤적·확장 파문 없이 작은 정적 명중 표시만 남긴다. 효과는 저장하지 않으며 새 보드/복원 시 비운다.
- 원화 전체의 기울기/이동/스케일 및 별도 효과를 결합한 **절차적 표현**이다.
  팔·몸통 도형 캐릭터나 공통 기사로 대체하지 않았으며,34종 고유 전신 프레임을 새로 만든 것이 아니다.
- 기존7계열 attack행은 전신 공통 캐릭터라 개별 원화와 바꾸면 정체성이 달라진다.
  이번에는 그 행을 억지로 겹치지 않는다. 적의 기존 공유 walk/idle 애니메이션은 유지한다.
- 새 이미지는 생성하지 않았다. 제공 도구가 모델 ID/등급을 검증할 수 없으므로 최상위 이미지 모델을
  사용했다고 주장하지 않는다. 후속 고유 프레임 제작에는 확인 가능한 모델과 기존 sprite-gen 프롬프트 절차가 필요하다.

## 규칙 불변성 증거

사용자가 재강조한 [aldegad/sprite-gen](https://github.com/aldegad/sprite-gen)의 실제 프롬프트
출처는 이 저장소의 `assets/art/families/<family>/sprite_run/prompts/attack.txt`이다.
대응 가이드는 `sprite_run/references/layout-guides/attack.png`, 규격은 각 family의
`manifest.json`에 남아 있다. humanoid의 실제 파일을 다시 읽어6프레임·256×256셀·24px안전 여백,
정체성 유지와 공격/회복 규약을 확인했다. 기존 제작 경로와 모델 미확인 상태는
`pipeline-receipt.json`에 그대로 보존한다. **이번 변경에서 생성 프롬프트를 실행하거나 새 프레임을
제작한 범위는 없다.** 코드로 그리는 궤적/파편은 별도의 런타임 효과이며 sprite-gen 생성 산출물로
표현하지 않는다. 다음 실제 이미지 제작 때는 sprite-gen의 **준비/프롬프트 생성 단계까지만**
실행하여 본인 작업의 중간 프롬프트 파일과 프레임 가이드를 얻는다. GPT/Grok API 키를 설정하거나
sprite-gen으로 외부 이미지 API 전송·유료 호출을 하지 않는다. 추출한 실제 프롬프트·가이드를
대화 이미지 생성 도구로 전달하는 경로이며, 임의 대체 프롬프트를 sprite-gen 산출물로 표시하지 않는다.
이 절차는 네트워크 트래픽 가로채기가 아니다. 최상위 모델 검증 조건은 별도로 충족해야 하고,
확인 불가 상태를 낮은 모델 사용 승인으로 해석하지 않는다.

기본 커밋의 simulation.gd를 별도 임시 스크립트로 로드하여 현재 코드와 같은 시드712,
34용병으로1,800틱(각1/30초)을 나란히 실행했다. 현재 쪽에 표시 신호/포즈 계산을 연결하고
각 틱의 snapshot, 기존 effects와 RNG 상태를 비교했다. run_id의 실제 생성시간만 동일 값으로 맞췄다.
`BASELINE_DIFFERENTIAL_PASS`: 모든 틱에서 동일. 로그: `artifacts/logs/animation-differential.log`.
이는60게임초 비교이며 모든 가능한 게임 상태에 대한 수학적 증명은 아니다.

## 재현 명령

```bash
bash scripts/web-setup.sh
VERIFY_VISUAL=1 bash scripts/verify.sh
# 개별 렌더 시퀀스는 아래에 기록한 capture 명령을 사용한다.
bash scripts/web-export.sh
python3 scripts/web-serve.py --host 127.0.0.1 --port 4173
# 별도 터미널에서, 캐시는 작업 폴더로 격리한다.
npm_config_cache="$PWD/artifacts/npm-cache" npm ci --prefix tools/web
node tools/web/browser-qa.cjs --base-url http://127.0.0.1:4173/ --output artifacts/animation-web-qa
```

공개 배포는 하지 않았다. 캡처는 아래 환경으로 재현한다.

```bash
export PATH="$PWD/.godot-tools/os/usr/bin:$PATH"
export XDG_DATA_HOME="$PWD/artifacts/user-data"
export XDG_CONFIG_HOME="$PWD/artifacts/user-config"
export XDG_CACHE_HOME="$PWD/artifacts/user-cache"
timeout --kill-after=5s 90s xvfb-run -a -s '-screen 0 900x1400x24' env LIBGL_ALWAYS_SOFTWARE=1 .godot-tools/4.7.2-stable/godot --path . --audio-driver Dummy --rendering-method gl_compatibility --resolution 720x1280 --script res://tests/animation_capture.gd -- --ui-test
```

## 검증 결과와 인계 범위

- 최종 Godot import, 계약/저장/아트/표현 검사 **33개**, 메인 장면300회 반복,
  실제 네이티브 UI 입력 검사 **183개** 통과. 오류0. `artifacts/logs/animation-final-verify.log`,
  `contracts.log`, `ui-scenario.log`에 기록했다.
- 실제 공격을 발생시킨720×1280 렌더에서 준비→공격→회복과 베기/활/시전/찌르기를 확인했다.
  45연속 프레임(1/30게임초 간격)과 상태별7장을 출력했다. 캡처 검사의 오류0,
  정지한 두 프레임은 픽셀 단위로 동일했다. 일부 연속 프레임과 상태별 화면을 이미지 도구로 열어
  원화 정체성과 효과를 확인했으며 수동 플레이테스트를 했다는 뜻은 아니다.
  결과: `artifacts/logs/animation-capture.log`, `artifacts/animation/`.
- 최종 Web export와 Chromium 자동 QA **12개 그룹** 통과, 브라우저 오류0.
  저장/재개·배속·정지·패널·이동·모바일 터치·넓은 화면·일반URL의 QA 접근 차단을 검사했다.
  결과: `artifacts/animation-web-qa/report.json`, `artifacts/logs/animation-web-qa.log`.
- 이번 변경의 Android APK/물리 모바일 기기 검사는 수행하지 않았다.
- 이미지·영상·엔진·로그·의존성 캐시는 Git에 넣지 않는다. 다른 환경에서는 위 명령으로 재현한다.
- 별도 검토 작업자가 표시 계층 계약과 테스트를 검토했고, 투창/내려치기 준비 효과의 구분을 보완했다.
  작업자 요청 설정은 gpt-6-luna/medium이며 실제 모델 메타데이터와 전체 사용량은 확인할 수 없다.

새 고유 애니메이션 프레임 제작은 남아 있다. 최상위 이미지 모델을 검증할 수 없는 현재 상태에서는
생성을 보류하며, 이후 실제 sprite-gen 중간 프롬프트와 가이드를 사용하는 제약을 유지한다.
