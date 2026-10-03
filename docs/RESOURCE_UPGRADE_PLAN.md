# 전체 게임 리소스 보강 계획

이 문서는 제작 범위와 검증 계약이다. 생성·패킹·런타임 연결·이미지 검토·실제 화면 검증의 누적 진척은 통합 담당자가 별도로 관리한다. 이 계획에 항목이 있다는 이유로 제작 완료를 뜻하지 않는다.

카탈로그와 기존 표시 계층의 조사 기준 커밋은 `6960fb8`이다. 이후 같은 작업 브랜치에서 진행 중인 구현과 생성물을 덮어쓰지 않는다. 기계 판독용 상세 목록은 [`tools/art/identity-plan.json`](../tools/art/identity-plan.json)에 있다.

## 1. 완료 범위와 순서

| 구분 | 정체성 수 | 필수 상태 | 새 행 수 | 자세 수 |
| --- | ---: | --- | ---: | ---: |
| 아군 용병 | 34 | attack, idle | 68 | 408 |
| 일반 적 | 40 | walk | 40 | 240 |
| 보스·최종 보스 | 10 | walk | 10 | 60 |
| 특수 적 | 3 | walk | 3 | 18 |
| 합계 | 87 | 정체성별 필수 상태만 | 121 | 726 |

1. 먼저 아군 공격 34행과 적 이동 53행, 총 87행·522자세를 완성한다. 검증된 묶음부터 누적 연결하되 남은 정체성을 완료로 처리하지 않는다.
2. 아군 idle 34행·204자세를 보강한다. 기존 attack을 보존하고 상태 전환의 크기·발 기준점을 맞춘다.
3. 피격·죽음·탈출·상태이상·배치·소환·조합 표시와 메모리 예산을 검증하고 통합 검사를 끝낸다.

사용자는 전체 리소스 보강과 필요한 새 스프라이트의 내장 이미지 생성을 승인했다. 이미지 생성은 실제 sprite-gen 유래 프롬프트를 사용한다. GPT/Grok 외부 이미지 API나 유료 API 호출을 사용하지 않는다.

### 실제 게임 규칙에 없는 상태는 만들지 않는다

- 적은 경로를 이동하고 탈출 시 목숨을 차감한다. 아군을 공격하지 않는다.
- 아군에는 HP·피격·전투 사망이 없다. 아군 hit/death와 적 attack 행은 제작하지 않는다.
- 아군 배치는 즉시 셀 변경/교환이다. 별도의 보행 시뮬레이션을 추가하지 않고 선택·드래그·도착 표시로 보강한다.
- 적이 기절한 동안에는 자기 정체성의 정지 기준 자세를 재사용한다. 현재 게임에 적 53종의 별도 idle 행은 필요하지 않다.
- 피격·사망은 기존 개별 스프라이트에 짧은 색 변화·반동·소멸 표시를 적용해도 된다. 이를 새로 그린 전신 hit/death 프레임이라고 표현하지 않는다.

## 2. 원화와 프롬프트의 권위

각 정체성의 기준은 **현재 `assets/art/portraits/<id>.png`의 실제 픽셀**이다. 과거 묶음 시트, 설명의 색상, 카탈로그 family보다 우선한다. 생성 직전에 해당 개별 파일을 열어 확인한다. 계획 JSON에 기준 경로와 SHA-256을 기록해 원화 변경을 감지한다.

중요한 예외:

- u03은 실제 개별 원화의 **파란 보석 지팡이와 짙은 파란 의상**을 유지한다. 과거 묶음의 보라색 설명을 다시 적용하지 않는다.
- u06은 family가 blob이지만 실제로는 역병 가면을 쓴 인간형 약제사다.
- u09는 몸에 묶인 북을 북채로 두드린다. 일반 망치 내려치기로 바꾸지 않는다.
- u10은 스라소니 한 마리와 탑승한 사냥꾼 한 명이다. 공격은 기수의 동작이며 고양이 물어뜯기가 아니다.
- u15 원화에 망치가 없다. 현 원화를 유지하는 이번 계약은 실제 돌주먹을 이용한다. 공격 행에만 망치를 새로 넣지 않는다.
- u24는 활잡이다. 총 발사 표현이 아니라 활시위 당김·화살 발사를 사용한다.
- n12는 거머리, n31은 해파리, n33은 불사조다. 각각 blob/floating/dragon이라는 계열명만으로 움직임과 몸을 대체하지 않는다.
- u18의 앉아 있는 까마귀, u34의 시계 장식, n38의 특징적인 장갑 조각처럼 정체성에 필요한 요소를 작은 연결 성분이라는 이유만으로 삭제하지 않는다.

### 고정 sprite-gen 출처

- 저장소: [aldegad/sprite-gen](https://github.com/aldegad/sprite-gen)
- 버전: `v2.17.0`
- 고정 커밋: `4a2ebdbcbb9e228b143ef10876ecd48261288df0`
- 확인한 템플릿 함수: [`sprite_gen/gen/prepare.py::row_prompt`](https://github.com/aldegad/sprite-gen/blob/4a2ebdbcbb9e228b143ef10876ecd48261288df0/sprite_gen/gen/prepare.py#L753-L826)
- 저장소에 보존된 실제 행 프롬프트: `assets/art/families/humanoid/sprite_run/prompts/attack.txt`

위 고정 소스의 정체성 고정·동작·프레임 배치·안전 여백 규약을 사용한다. 내장 도구에 맞춘 3열×2행 및 실제 알파 투명 배경 수정은 전송 프롬프트에 명시한다. 계획 JSON의 `motion_prompt`는 전체 유래 프롬프트에 넣을 정체성별 동작 절이며, 그 자체가 CLI를 새로 실행한 결과라고 주장하지 않는다.

새 CLI 준비·추출·검사를 실제로 실행했다면 명령과 산출물을 별도로 남긴다. 실행하지 않은 단계를 영수증에 넣지 않는다. 내장 이미지 도구가 모델 식별자/등급을 노출하지 않으므로 추론 모델 설정을 이미지 모델 증거로 사용하지 않는다.

## 3. 고정 경로와 산출물

| 용도 | 경로 |
| --- | --- |
| 상세 제작 계획 | `tools/art/identity-plan.json` |
| 정체성 기준 원화 | `assets/art/portraits/<id>.png` |
| 전송한 전체 프롬프트 | `docs/art-generation/<id>/<state>.prompt.txt` |
| 생성 원본 바이트 | `docs/art-generation/<id>/<state>.source.png` |
| 3열×2행 가이드 | `docs/art-generation/layout-guide-3x2.png` |
| 런타임 아틀라스 | `assets/art/identities/<id>/atlas.png` |
| 프레임·시간·크기 정보 | `assets/art/identities/<id>/layout.json` |
| 상태별 출처·검사·검토 기록 | `assets/art/identities/<id>/receipt.json` |
| 런타임 정체성 인덱스 | `assets/art/identity_animations.json` |

인덱스는 schema 1의 `identities`에서 각 ID의 `atlas`, `frame_layout`을 지정한다. 필수 상태는 해당 layout의 실제 행으로 검증한다. 생성 원본과 제작용 문서는 Godot 런타임 내보내기에서 제외한다.

**상태 추가는 누적 병합이다.** idle을 가져올 때 같은 ID의 attack 아틀라스·행·검토 증거를 삭제하지 않는다. 상태별 `render_scale`이 필요하면 각 상태에 맞게 보존하고, 첫/끝 자세의 실제 몸 크기와 발 기준점이 자연스럽게 이어지는지 화면에서 검증한다.

## 4. 이미지 규격과 패킹

- 정확히 여섯 완전한 자세, 3열×2행 읽기 순서, 실제 알파 투명 배경을 요청한다.
- 카메라·시선·손잡이·얼굴·팔레트·장비·정체성은 고정한다. 한 정지 이미지의 회전/스케일 복사 여섯 장으로 대체하지 않는다.
- 무기 끝, 뿔, 날개, 꼬리, 촉수까지 각 슬롯 안에 완전히 들어가야 한다. 원본 가장자리에서 잘린 자세를 패킹으로 복구했다고 주장하지 않는다.
- 기본 런타임 셀은 256×256, 발/지지 기준선은 y=232다. 한 상태의 여섯 자세에는 하나의 균일 배율을 적용한다.
- 무기를 포함한 외곽 박스 중심 대신 발/지지점 기준으로 정렬한다. 부유형·긴 장식형은 최하단 픽셀이 실제 발인지 별도 확인한다.
- 소스가 요청 배치를 어겼으면 실제 분할/연결 성분과 각 자세의 완전성을 검증한다. 이미지 폭을 기계적으로 6등분하지 않는다.
- 여러 연결 성분으로 구성된 정체성은 합법적인 부품을 보존한다. 가장 큰 여섯 성분만 고르는 방식이 모든 캐릭터에 통한다고 가정하지 않는다.
- 글자, 프레임 번호, 가이드 선, 배경, 바닥 그림자, 빛 번짐, 무기 궤적, 발사체와 별도 장식 효과를 캐릭터 프레임에 굽지 않는다. 관련 VFX는 표시 계층에서 분리한다.

승인받은 `6c554fc7`의 u01 예시는 동작 품질의 참고이며 그대로 런타임 아틀라스가 아니다. 원본의 불규칙 배치와 검 끝 여백 문제를 재검증해야 한다.

## 5. 애니메이션 시간 계약

### 공격: 2 준비 / 2 접촉·후속 / 2 회복

| 0부터 시작하는 프레임 | 의미 | 길이 |
| --- | --- | ---: |
| 0 | 준비 시작 | 90ms |
| 1 | 최대 준비 | 90ms |
| 2 | 실제 접촉·발사 | 60ms |
| 3 | 접촉 후속 동작 | 60ms |
| 4 | 회복 | 180ms |
| 5 | 기존 대기 자세 복귀 | 180ms |

`durations_ms = [90, 90, 60, 60, 180, 180]`, 반복 없음. 총 660ms이며 공격 전 180ms와 공격 후 480ms로 구성한다. durations가 있을 때 명목 fps보다 우선한다.

- 준비 시계: `clamp(0.18 - cooldown, 0, 0.18)`
- 실제 공격 이벤트 이후 시계: `0.18 + (simulation.time - event.time)`
- 첫 즉시 공격은 프레임 2에서 시작한다. 준비 동작 때문에 피해를 늦추지 않는다.
- 발사체는 표시용이다. 도착 시간 때문에 기존 즉시 피해 판정을 지연하거나 다시 계산하지 않는다.
- 새로 관절이 움직이는 프레임 위에 기존 원화 전체 기울기/확대를 과도하게 중복 적용하지 않는다.

### 이동

6프레임, 각 125ms, 기준 8fps 반복이다. 실제 적 이동량/속도에 비례한 표시 위상을 사용한다. 둔화와 기절 중에도 전속력 보행을 계속하지 않는다. 위상 계산 때문에 progress·CC·RNG를 변경하지 않는다. 경로 모서리에서 직립 캐릭터 전체를 90도 회전시키지 않는다. 다방향 정면/후면 프레임은 이번 고정 카메라 계약에 없는 별도 확장이다.

### 대기와 접근성

아군 idle은 6프레임, 각 167ms, 기준 6fps 반복이다. 호흡·천·갈기·날개 등 실제 형태 변화가 있어야 하며 정지 복제 행은 새 idle로 세지 않는다. 적 정지와 아직 idle이 준비되지 않은 아군에는 자기 원화/자기 대기 끝 자세를 재사용할 수 있으나 정적 대체 상태임을 구분한다.

모든 표시 시간은 게임시간을 따른다. 일시정지·설정·백그라운드·배속·reduced-motion·새 게임·복원을 검사한다. 정지 화면을 만들 때 공격 준비 프레임에 멈추지 말고 자기 정체성의 안정된 대기 자세를 사용한다.

## 6. 새 전신 행 없이 필요한 표시 보강

- 피격: 실제 피해를 입은 개별 적을 표시한다. 1차 목표뿐 아니라 splash 대상도 포함한다.
- 죽음: 적 제거 전에 정체성·좌표·시간이 있는 표시 이벤트를 만든다. 처치와 보상은 기존 시점 그대로 처리한다.
- 탈출: 죽음과 다른 출구 표시를 사용하고 처치 보상을 만들지 않는다.
- 승리: 최종 보스 사망으로 정리되는 살아 있는 적을 모두 처치 애니메이션으로 오인하지 않는다.
- 기절·둔화: 실제 상태와 이동 속도에 맞춘 표시를 사용한다.
- 배치·소환·조합: 선택, 드래그, 도착 및 조합 결과를 짧게 표시한다. 재료로 소비된 아군에게 전투 사망을 붙이지 않는다.

화면별 이전 스냅샷 차이만으로 사망을 추적하면 한 표시 간격 안에 생성·사망한 적을 놓칠 수 있다. 실제 변경 지점의 표시 이벤트가 필요하다. 표시 기록은 개수와 수명이 제한되고 저장하지 않으며 복원·새 실행에서 비운다.

## 7. 재사용할 정적 리소스

- 87종의 개별 초상/전신 원화 및 coin 원화
- `assets/art/backgrounds/guild.png`
- 실제 사용 중인 `assets/art/orthographic/battle-map.png`
- `assets/art/backgrounds/app-icon.png`
- `assets/ui/*.svg`와 동봉 폰트
- 무기·발사체·명중 효과의 공통 그리기 코드. 단, u24 등 장비와 어긋나는 매핑은 수정한다.

기존 7계열 프레임과 tint는 명시적인 대체 경로로만 유지한다. 87종의 고유 애니메이션 완성으로 세지 않는다. 과거 `assets/art/backgrounds/battlefield.png`는 현 전장 배경이 아니다. 통합 시 매니페스트가 실제 orthographic 경로를 설명하도록 고친다.

## 8. GPU 메모리와 해상도 예산

256×256 RGBA8 여섯 프레임은 밉맵·드라이버 오버헤드 전 1.5MiB다. core 87행은 130.5MiB, 전체 121행은 181.5MiB다. 압축 PNG 파일 크기는 GPU 상주량이 아니다. 기존 초상, 7계열 대체 아틀라스, 배경과 렌더 타깃은 이 수치에 포함하지 않는다.

- 초기 엔지니어링 목표: **고유 아틀라스 상주량 soft 96MiB / hard 128MiB**. 아직 측정 통과를 뜻하지 않는다.
- 실제 보이는 정체성의 아틀라스만 지연 로드한다. 100웨이브 동안 한 번 본 정체성을 모두 영구 캐싱하면 지연 로드만으로 예산이 지켜지지 않는다.
- 살아 있는 유닛/적, 남은 죽음 효과, 미리보기 등 참조가 없는 정체성을 안전한 시점에 해제하고 장면·실행 수명 주기에 캐시를 정리한다.
- 화면에 모든 34종 아군이 동시에 있다면 attack+idle만 102MiB다. 적과 기타 리소스까지 포함한 실제 Web/mobile GPU·RSS 최고치를 측정한다.
- 이후 필요하면 256px 마스터를 보존한 채 작은 화면 캐릭터에 128px 변형, 보스·큰 피사체에 256px을 적응적으로 사용한다. 128px 셀은 같은 행의 디코드 메모리를 1/4로 낮춘다. layout·기준점 정보를 함께 바꾸고 축소 가독성을 검증하며 잘라내기로 해상도를 맞추지 않는다.

## 9. 검증과 완료 판단

1. 카탈로그 ID 87개와 필수 상태 121행이 정확히 일치하고 누락·중복이 없는지 확인한다.
2. 각 행 여섯 자세의 알파·범위·프레임 크기·타이밍·SHA-256·출처 기록을 확인한다.
3. 전체 순서를 직접 열어 정체성, 장비, 팔다리 수, 연결, 실제 관절 동작, 잘림, 기준점, 크기, 루프 연결을 검사한다. 점수 자동 통과를 시각 검토로 부르지 않는다.
4. 34종 공격과 53종 적의 실제 표시를 캡처하고 대기↔공격, 정지/배속/reduced-motion, 둔화/기절, 복원과 새 게임을 검사한다.
5. splash, 동시 처치, 탈출, 최종 승리 정리, 빠른 연속 공격이 simulation snapshot·RNG·보상·저장 계약을 바꾸지 않는지 확인한다.
6. 최종 통합 스냅샷에서 `VERIFY_VISUAL=1 bash scripts/verify.sh`, Web export와 browser QA를 실행한다. Android/물리 기기를 실행하지 않았다면 별도로 미검증이라고 밝힌다.
7. 생성, 패킹, 런타임 연결, 원본/아틀라스 이미지 검토, 실제 화면 검증을 분리해 보고한다. 일부 묶음만으로 전체 리소스 완료를 선언하지 않는다.

## 10. 전체 ID 체크리스트

각 행의 세부 동작과 해부·장비 보호 조건은 JSON의 `states.<state>.motion_prompt`와 `anatomy_weapon_safeguards`에 있다. 아래 표는 제작 대상이며 진척 체크 표시가 아니다.

| ID | 이름 | 카탈로그 구분 | 계열 | 필수 상태 |
| --- | --- | --- | --- | --- |
| u01 | 길드 검사 | units | humanoid | attack, idle |
| u02 | 숲길 궁수 | units | humanoid | attack, idle |
| u03 | 견습 마도사 | units | humanoid | attack, idle |
| u04 | 수도사 | units | humanoid | attack, idle |
| u05 | 길드 사제 | units | floating | attack, idle |
| u06 | 늪지 약제사 | units | blob | attack, idle |
| u07 | 왕실 창기사 | units | humanoid | attack, idle |
| u08 | 룬 저격수 | units | humanoid | attack, idle |
| u09 | 전쟁 북장이 | units | heavy | attack, idle |
| u10 | 설원 사냥꾼 | units | quadruped | attack, idle |
| u11 | 철갑 수호자 | units | heavy | attack, idle |
| u12 | 폭풍 검무가 | units | humanoid | attack, idle |
| u13 | 대현자 | units | floating | attack, idle |
| u14 | 황금 고블린 | units | humanoid | attack, idle |
| u15 | 용암 거인 | units | heavy | attack, idle |
| u16 | 고대 비룡 | units | dragon | attack, idle |
| u17 | 해적 총잡이 | units | humanoid | attack, idle |
| u18 | 황혼 주술사 | units | floating | attack, idle |
| u19 | 수정 정령 | units | blob | attack, idle |
| u20 | 사막 투창병 | units | humanoid | attack, idle |
| u21 | 성채 연금술사 | units | humanoid | attack, idle |
| u22 | 은빛 성기사 | units | heavy | attack, idle |
| u23 | 독안개 현자 | units | floating | attack, idle |
| u24 | 천둥 사수 | units | humanoid | attack, idle |
| u25 | 얼음 무희 | units | humanoid | attack, idle |
| u26 | 철혈 사령관 | units | heavy | attack, idle |
| u27 | 그림자 검객 | units | humanoid | attack, idle |
| u28 | 태양 사제 | units | floating | attack, idle |
| u29 | 별빛 도사 | units | floating | attack, idle |
| u30 | 숲의 파수꾼 | units | quadruped | attack, idle |
| u31 | 폭풍 군주 | units | heavy | attack, idle |
| u32 | 월식 여왕 | units | multi | attack, idle |
| u33 | 성역 수호룡 | units | dragon | attack, idle |
| u34 | 시간의 관측자 | units | floating | attack, idle |
| n01 | 고블린 정찰병 | normal | humanoid | walk |
| n02 | 늑대 약탈자 | normal | quadruped | walk |
| n03 | 슬라임 | normal | blob | walk |
| n04 | 해골 전사 | normal | humanoid | walk |
| n05 | 거미 추적자 | normal | multi | walk |
| n06 | 숲의 망령 | normal | floating | walk |
| n07 | 오크 돌격병 | normal | heavy | walk |
| n08 | 어린 와이번 | normal | dragon | walk |
| n09 | 가시 멧돼지 | normal | quadruped | walk |
| n10 | 동굴 박쥐 | normal | floating | walk |
| n11 | 붉은 도적 | normal | humanoid | walk |
| n12 | 늪 거머리 | normal | blob | walk |
| n13 | 바위 게 | normal | multi | walk |
| n14 | 불꽃 정령 | normal | floating | walk |
| n15 | 회색 늑대 | normal | quadruped | walk |
| n16 | 장갑 고블린 | normal | heavy | walk |
| n17 | 서리 슬라임 | normal | blob | walk |
| n18 | 밤의 추적자 | normal | humanoid | walk |
| n19 | 독거미 | normal | multi | walk |
| n20 | 고대 골렘 | normal | heavy | walk |
| n21 | 사막 전갈 | normal | multi | walk |
| n22 | 유령 기사 | normal | humanoid | walk |
| n23 | 붉은 와이번 | normal | dragon | walk |
| n24 | 얼음 거수 | normal | quadruped | walk |
| n25 | 맹독 슬라임 | normal | blob | walk |
| n26 | 화산 투사 | normal | heavy | walk |
| n27 | 황혼 정령 | normal | floating | walk |
| n28 | 칼날 사마귀 | normal | multi | walk |
| n29 | 검은 사냥개 | normal | quadruped | walk |
| n30 | 폐허 주술사 | normal | humanoid | walk |
| n31 | 구름 해파리 | normal | floating | walk |
| n32 | 철갑 거북 | normal | quadruped | walk |
| n33 | 불사조의 잔영 | normal | dragon | walk |
| n34 | 심연의 문어 | normal | multi | walk |
| n35 | 흑요석 거인 | normal | heavy | walk |
| n36 | 달빛 망령 | normal | floating | walk |
| n37 | 수정 용 | normal | dragon | walk |
| n38 | 균열 수호병 | normal | heavy | walk |
| n39 | 마왕의 전령 | normal | humanoid | walk |
| n40 | 공허 비룡 | normal | dragon | walk |
| b10 | 도보 도적왕 | boss | humanoid | walk |
| b20 | 숲의 거목 | boss | heavy | walk |
| b30 | 거미 여왕 | boss | multi | walk |
| b40 | 심연의 망령 | boss | floating | walk |
| b50 | 고대 슬라임 | boss | blob | walk |
| b60 | 빙설 거수 | boss | quadruped | walk |
| b70 | 화산 거인 | boss | heavy | walk |
| b80 | 폭풍 와이번 | boss | dragon | walk |
| b90 | 타락한 용기사 | boss | humanoid | walk |
| b100 | 마왕 | boss | dragon | walk |
| s10 | 골드 고블린 | special | humanoid | walk |
| s30 | 황금 고블린 | special | humanoid | walk |
| s60 | 도적 두목 | special | heavy | walk |
