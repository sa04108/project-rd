# 리소스 제작 안내

이미지·스프라이트 프레임·음악·효과음의 실제 생성/편집과 최종 산출물 제작은 루트 에이전트가 직접 수행한다. 서브에이전트는 조사·프롬프트 초안·제작 도구 코드·검토를 지원한다. 현재 제작 잔여량과 미검증 항목은 [REMAINING](REMAINING.md)에만 기록한다.

## 기준과 파일 역할

- 게임 동작은 [게임 규칙](GAME_RULES.md), 캐릭터 외형은 현재 `assets/art/portraits/<id>.png`의 실제 픽셀이 기준이다. 생성 전에 해당 원화를 직접 연다. 과거 묶음 시트·family 이름·설명과 충돌하면 현 원화를 우선한다.
- [identity-plan.json](../tools/art/identity-plan.json)은 정체성·필수 동작·해부/장비 보호 조건을 담은 제작 입력이다. 계획에 있다는 사실은 생성·연결·검증 완료를 뜻하지 않는다.
- 실제 고유 프레임은 [identity_animations.json](../assets/art/identity_animations.json)과 각 `layout.json`의 상태를 읽어 확인한다. 현재 87종에 아군 공격 34행·대기 34행·적 이동 53행, 총 121행/726프레임이 연결돼 있다. 원화, 공유 계열, 고유 애니메이션을 별도로 세며 등록 수만으로 동작 품질을 판정하지 않는다.
- 새 리소스를 추가하기 전에 기존 표현과 재사용 가능성을 확인한다. 아군에 없는 hit/death나 적의 attack 행은 만들지 않는다. 적 기절은 자기 정체성의 정지 자세를 재사용한다.
- 원본·전송 프롬프트·출처·라이선스를 보존하고, 일회성 미리보기·중복 추출본·검사 캡처는 `artifacts/`에 둔다. 샘플용 HTML·문서·생성 스크립트를 납품물로 남기지 않는다.

| 용도 | 경로 |
|---|---|
| 캐릭터 기준 원화 | `assets/art/portraits/<id>.png` |
| 실제 전송 프롬프트·생성 원본·수리 기록 | `docs/art-generation/<id>/` |
| 3열×2행 배치 가이드 | `docs/art-generation/layout-guide-3x2.png` |
| 개별 런타임 아틀라스·메타데이터·출처 | `assets/art/identities/<id>/{atlas.png,layout.json,receipt.json}` |
| 고유 프레임 인덱스 | `assets/art/identity_animations.json` |
| 공유 계열 대체 경로와 카탈로그 매핑 | `assets/art/families/`, `assets/art/manifest.json` |
| 배경·UI·폰트 | `assets/art/backgrounds/`, `assets/art/orthographic/`, `assets/ui/`, `assets/fonts/` |
| 음악·버튼·전투 음원과 출처 | `assets/audio/{music,ui,combat}/`, `assets/audio/LICENSE.txt` |

`docs/art-generation/`은 제작 도구와 receipt가 직접 참조한다. 일반 보고서처럼 삭제하거나 옮기지 않는다. `.gdignore`와 export 제외 설정으로 제작 원본을 게임에서 분리한다. 채택하지 않은 수리 후보를 런타임 원본으로 자동 승격하지 않는다.

## 개별 캐릭터 프레임

sprite-gen의 버전은 `v2.17.0`, 출처 커밋은 `4a2ebdbcbb9e228b143ef10876ecd48261288df0`이다. [row_prompt 템플릿](https://github.com/aldegad/sprite-gen/blob/4a2ebdbcbb9e228b143ef10876ecd48261288df0/sprite_gen/gen/prepare.py#L753-L826)과 저장소의 `assets/art/families/<family>/sprite_run/prompts/`를 사용한다. 준비된 프롬프트·가이드를 내장 이미지 도구에 전달하며 외부 GPT/Grok 이미지 API나 유료 API를 호출하지 않는다. 내장 도구의 모델 ID/등급이 노출되지 않으면 추정하지 않는다.

1. 현 원화와 해당 ID의 `anatomy_weapon_safeguards`, `motion_prompt`를 확인한다. u09는 북, u10은 스라소니 위 기수, u15는 돌주먹, u24는 활이다. u06을 family 이름만 보고 덩어리 몸체로 바꾸지 않는다. 부유 장식·까마귀·시계도 정체성의 일부일 수 있다.
2. Python 3와 Pillow·NumPy·SciPy 환경에서 프롬프트를 준비한다. 아래 명령의 `u01`/`attack`은 원하는 ID/상태로 바꾼다. 기존 실제 전송 파일이 있으면 도구가 덮어쓰기를 거부한다. 기존 파일을 재사용하고 수리 요청은 별도 이름으로 보존한다.

   ```bash
   python3 tools/art/prepare_identity_prompts.py u01 --state attack
   ```

3. 루트가 전체 프롬프트·원화·배치 가이드로 생성한다. 정확히 여섯 완전한 자세, 3열×2행 읽기 순서, 실제 투명 알파를 요청한다. 각 슬롯 사방에 충분한 여백을 두고 장비·팔다리·꼬리까지 포함한다. 정지 이미지의 회전/확대 복사를 독립된 자세로 세지 않는다.
4. 루트가 여섯 자세를 직접 열어 정체성·무기·팔다리 수·연결·동작·잘림을 확인한다. 이미지 수정은 내장 이미지 도구로 수행한다. 글자·가이드·그림자·발사체·무기 궤적은 프레임에 굽지 않는다. 실제 전송 내용과 결과를 `<state>.prompt.txt`, `<state>.source.png`로 보존한다.
5. 검토한 원본을 루트가 패킹한다. 기본 경로는 연결 성분을 사용한다. 정체성에 떨어진 장식이 있으면 `--ornaments`, 완전한 3×2 구획을 확인했으면 `--grid`를 검토한다. 임의로 실패를 우회하지 않는다.

   ```bash
   python3 tools/art/import_identity.py u01 --state attack
   ```

6. 생성된 atlas·layout·receipt와 인덱스 변경을 확인한다. 패킹은 256×256 셀, 지지 기준선 y=232, 상태 전체에 한 균일 배율을 사용한다. 무기 포함 외곽 중심 대신 발/지지점을 맞추고, 상태별 `render_scale`로 원화 대비 몸 크기를 검증한다. 잘린 원본을 패킹으로 복구했다고 하지 않는다.
7. 상태 추가는 기존 행을 보존하는 누적 병합이다. idle을 추가하며 attack을 잃거나 다른 상태의 크기·출처를 덮지 않는다. 도구가 쓰는 정형 review 문구만으로 시각 검토 완료를 증명하지 않는다. 실제 검사·수리·화면 확인 결과를 해당 리소스 기록에 반영한다.
8. [개발 안내](DEVELOPMENT.md)에 따라 Godot 리소스를 다시 가져오고, 게임 안에서 실제 프레임과 애니메이션을 직접 살펴본다. 원본 검토, 패킹 결과 확인, 실제 게임 렌더링은 각각 구분한다.

### 동작과 시간

- 공격은 여섯 프레임에 `[90,90,60,60,180,180]`ms, 반복 없음이다. 앞 180ms는 준비, 이후 480ms는 접촉·회복이다. 준비 시계는 `clamp(0.18-cooldown,0,0.18)`, 실제 공격 뒤는 `0.18 + simulation.time - event.time`이다. 첫 즉시 공격은 접촉 프레임부터 시작해 피해를 늦추지 않는다.
- 이동은 125ms×6, 기준 8fps 반복이다. 실제 진행 거리/속도에 따라 표시 위상을 계산하고 둔화·기절·정지에 맞춘다. 경로 모서리에서 직립 캐릭터를 90도 돌리지 않는다.
- 대기는 호흡·천·갈기·날개 등의 미세한 실제 자세 변화로 만든다. 현재 34종 런타임 layout과 패킹 도구는 250ms×6, 4fps 반복이다. 필수 상태·정체성은 제작 계획, 실제 재생 시간표는 각 layout의 `durations_ms`를 따른다.
- 정지·reduced-motion·복원에는 자기 정체성의 안정된 자세를 사용한다. 표시 때문에 cooldown·progress·RNG를 바꾸거나, 새 프레임 위에 전체 이미지 회전/확대를 과도하게 중복 적용하지 않는다.
- 아군 34종의 무기·속성 효과와 지원형 6종의 오라는 `combat_visuals.gd`, 적 53종의 재질·상태·피격/제거 표현은 `encounter_visuals.gd`가 소유한다. 적의 공격 동작을 추가하지 않는다.
- 피격·사망·탈출·소환·조합은 실제 사건과 맞춘 짧은 표현을 사용한다. 범위 피해의 부대상, 승리 시 일괄 정리, 조합 재료 소비를 구분하고 기존 보상·승패 시점을 보존한다. 표시 기록은 수명·개수를 제한하고 저장하지 않는다.

## 공유 계열과 초상

공유 7계열은 humanoid·heavy·quadruped·multi·floating·blob·dragon이다. 각 계열의 idle/walk/attack은 256×256 셀 여섯 프레임이며 고유 동작이 없는 경우의 대체 리소스다. 제작 원본은 각 `sprite_run/`의 `.gdignore` 아래에 보존한다.

계열을 변경해야 할 때만 고정 버전 sprite-gen의 준비된 프롬프트·가이드를 사용하고 루트가 내장 도구로 생성한다. 외부 설치 위치는 세션마다 다를 수 있다. 실제 설치를 확인한 CLI로 `extract --run-dir <run>`, `compose-atlas --run-dir <run>`, `inspect --run-dir <run> --states idle,walk,attack`, `score --inspect-report <report>` 순서의 필요한 단계를 실행한다. 연결된 실루엣은 `--segmentation projection` 등 실제 분할 결과를 확인한다.

```bash
python3 tools/art/import_family.py humanoid
python3 tools/art/build_manifest.py
python3 tools/art/validate_manifest.py
```

`--allow-unreviewed`는 자동 검사 실패 상태를 명시해 가져오는 옵션이며 검토 통과를 뜻하지 않는다. 기존 receipt의 `human_visual_review` 이름만 보고 사람이 검사했다고 주장하지 않는다. 캐릭터 목록과 환경 경로에 대한 매니페스트의 설명도 실제 런타임과 대조한다.

초상 묶음은 [portrait_batches](../tools/art/portrait_batches/)의 원본·정확한 순서·프롬프트를 보존한다. 고정 버전 sprite-gen의 `slice-sheet`와 기존 `import_batch.py`를 사용하되 명령 인자를 먼저 확인한다. 추출된 개별 파일의 알파·가장자리·넓은 장비를 검토한 뒤 등록하며, 중복 cutout과 재생성 가능한 캐시는 추가하지 않는다.

## 배경·UI·폰트

- [UI 레퍼런스 모음](art-generation/ui-reference.jpg)은 구성·색감·장식의 참고 원본으로 보존한다. 이미지 속 옛 수치·방어력·배속·기능은 현재 게임 규칙을 덮어쓰지 않는다.
- 실제 메뉴 배경은 `assets/art/backgrounds/guild.png`, 전장 주변 풍경은 `assets/art/orthographic/battle-map.webp`다. 지면은 같은 폴더의 `meadow-grass.webp`·`meadow-dirt.webp`를 `game/terrain_blend.gdshader`로 혼합한다. `backgrounds/battlefield.png`와 `orthographic/battle-map.png`는 현재 화면 경로가 아니다.
- 전장 그림은 소실점 없는 정투영과 720×1280 화면 구성을 따른다. 중앙 6×6칸과 폭 1칸인 외곽 길의 기준선은 엔진 좌표로 정의한다. 셰이더는 위치 기반 잡음으로 풀·흙의 가장자리만 부드럽고 불규칙하게 섞는다. 북서쪽 출입구는 하나이며 출입구/길드 글자·격자·웨이브·비용·문구를 원화에 굽지 않는다. 배치 격자는 드래그 중에만 엔진에서 표시한다.
- `assets/ui/diamond.svg`는 이 프로젝트용으로 직접 제작한 투명 배경 벡터 아이콘이다. `UiSkin`의 공통 텍스처 캐시와 `CurrencyLabel`을 통해 모든 다이아몬드 표시에 재사용하며 외부 이미지나 아이콘 폰트에 의존하지 않는다.
- `assets/ui/*.svg`의 패널·버튼은 9분할 가능한 금색 테두리·청색·양피지 장식이다. 실제 클릭 영역과 작은 화면의 글자 가독성을 함께 검증한다.
- 일반 UI는 영어·한국어용 `GuildSans.otf`, 간체 중국어용 `GuildCjkSC.otf`, 일본어용 `GuildCjkJP.otf`와 명시적 기호 fallback을 유지한다. CJK 두 폰트는 지역별 한자 자형을 보존한 Noto Sans CJK 부분집합이다. [출처와 재생성 방법](../assets/fonts/CJK-SOURCE.txt)에 따라 `tools/fonts/build_locale_fonts.py`로 현재 번역에 필요한 글자를 추린다. 새 번역을 추가하면 반드시 다시 생성하고 누락 글리프를 확인한다.
- 메뉴 영문 제목은 별도 세리프 폰트를 사용하며 배경 패널 없이 표현한다. 새 문구·기호, 실제 작은 화면의 폭·가독성을 확인하고 각 폰트 라이선스를 내보내기에 포함한다. 시스템 fallback에 기대어 검증하지 않는다.

## 음향

- 장시간 반복 청취에 부담 없는 은은한 질감이 기준이다. 검·활은 물리적인 바람 가름/시위 질감을 사용하며 불필요한 전자음·치찰음·긴 공기 잔향을 줄인다. 참고 소스의 사용 조건을 확인하고 [LICENSE.txt](../assets/audio/LICENSE.txt)에 출처를 보존한다.
- 음악은 `mist_guard.ogg`를 루프로 사용한다. UI는 `tap.wav`와 `chime.wav`만 사용하며 선택 UI나 나무 클릭음을 다시 추가하지 않는다. 역할은 [게임 규칙](GAME_RULES.md)에 정의한다.
- 공격음은 무기/동작별로 재사용한다. 같은 파일을 용병마다 복제하지 않고 `game/audio_director.gd`의 `UNIT_SOUNDS`에서 실제 장비와 연결한다. 새 용병이 추가되면 누락 없이 매핑한다.
- 짧은 효과음은 현재 모노 PCM16/22.05kHz WAV를 사용한다. 과한 정규화·클리핑을 피하고 짧은 감쇠와 마지막 40ms 무음으로 끝을 정리한다. `.import`는 `compress/mode=0`, `edit/normalize=false`, `edit/trim=false`로 잔향/레벨을 보존한다. 다른 포맷을 도입하면 디코드·청감·용량을 함께 확인한다.
- 실제 공격 이벤트, UI 성공/실패 흐름, 배경 전환에 연결해 검사한다. 효과음은 최대 동시 공격 보이스 3개, 전체 공격 간격 160ms, 같은 소리 간격 320ms 제한을 유지한다. 효과음 변주는 별도 RNG를 사용한다.
- 음악/효과음 독립 음소거, 루프 이음새, 빠른 입력과 ×5 배속의 누적 음량, 새 게임/복원/포커스 전환, 실제 지원 기기의 청감·진동을 검증한다. headless/Dummy 오디오 검사는 실제 청취 검사가 아니다.

## 이미지 파일 용량·압축

- 기존·신규 리소스는 파일당 약 **1 MB(1,000,000바이트) 이하를 권장**한다. 강제 제한이나 빌드 실패 조건이 아니며, 표현·투명도·경로·임포터 호환성을 먼저 보존한다. 현재 87개 고유 런타임 아틀라스는 모두 이 권장치 미만이다.
- 런타임 아틀라스는 디코딩 RGBA와 크기가 완전히 같은 PNG 무손실 압축만 적용한다. 알파를 양자화하거나 용량만을 이유로 자동 축소하지 않는다. 제작 시트/배경의 손실 후보는 명시적 선택과 시각 검토가 필요하다.
- 제작 시트 148개의 변환 근거는 [source-optimization.json](art-generation/source-optimization.json)에 보존한다. A=0 영역의 RGB만 정리한 파생본으로 알파·보이는 RGB는 정확히 같고, 기록된 절감량은 104,826,421바이트다. 생성 원본과 현재 파일의 SHA-256을 구분하고 이전 Git 이력을 유지한다. 완전 투명 RGB가 달라지므로 이를 RGBA 전체 동일이라고 부르지 않는다.

`tools/art/optimize_images.py`는 Pillow 기반 독립 CLI다. 기본 실행은 명시한 저장소 내부 8비트 RGB/RGBA PNG를 읽어 JSON만 표준 출력으로 내보내며 파일을 쓰지 않는다. 디렉터리를 자동 순회하지 않고 파일·상위 디렉터리의 심볼릭 링크를 건너뛴다. 팔레트/16비트 PNG와 APNG는 별도 검토 대상이다.

| 방식 | 픽셀 계약과 허용 범위 |
|---|---|
| `png-lossless` | 기본값. 크기·RGBA 완전 동일, RGB/RGBA 유형 유지 |
| `png-clean-alpha0` | A=0 RGB만 정리, 알파·보이는 RGB 동일. source/background 역할과 `--allow-transparent-rgb-cleanup` 필요 |
| `png-rgb` | RGB를 최대 256색으로 줄이고 원본 알파 복원. source/background 역할과 `--allow-lossy`, 품질 하한 필요 |
| `webp-lossless` | 디코딩 RGBA 동일 여부를 비교하며 외부 미리보기로만 출력 |
| `webp-lossy` | RGB 손실 후보 비교·외부 미리보기만 지원, 모든 알파·크기는 동일해야 함 |

WebP도 투명도를 지원하지만 기존 PNG 임포터/경로를 자동 교체하지 않는다. PNG 부가 청크를 보존하며 WebP는 ICC/EXIF/XMP만 복사한다. gamma/chromaticity/resolution 변환과 색 관리, 필터링 가장자리, 플랫폼 아이콘 요건은 별도로 확인한다.

```sh
# 읽기 전용 비교: 리소스·백업·미리보기 파일을 쓰지 않는다.
python3 -B tools/art/optimize_images.py assets/art/identities/u01/atlas.png

# 다섯 방식의 후보와 영수증은 명시한 저장소 밖 경로에만 쓴다.
OUT="$(dirname "$PWD")/image-size-review"
python3 -B tools/art/optimize_images.py \
  docs/art-generation/u01/attack.source.png \
  --method compare --role source \
  --preview-dir "$OUT/previews" --receipt "$OUT/comparison.json"

# 검토·승인한 PNG만 교체하며 저장소 밖 원본 백업이 필수다.
BACKUP="$(dirname "$PWD")/resource-original-backups"
python3 -B tools/art/optimize_images.py \
  assets/art/identities/u01/atlas.png --apply --backup-dir "$BACKUP"
```

- source/background 역할에서만 `png-clean-alpha0 --allow-transparent-rgb-cleanup` 또는 `png-rgb --allow-lossy`를 선택할 수 있다. 런타임 아틀라스에 source 역할을 지정해 제한을 우회하지 않는다. A=0 RGB 정리도 필터링 경계는 검토한다.
- `--apply`는 저장소 밖 고유 백업 디렉터리와 사전 영수증을 만든 뒤 파일별로 원자 교체한다. 평가 이후 원본 바이트가 달라지면 적용하지 않는다. 배치 전체는 하나의 트랜잭션이 아니므로 파일별 결과와 복구 경로를 확인한다.
- 영수증에는 이전/이후 바이트·SHA-256·크기·모드·RGBA/알파 해시·알파 분포·오차·백업 위치를 남긴다. 백업·비교 영수증·미리보기 출력 경로는 저장소 밖이어야 한다. 채택된 변환의 출처/해시 근거는 기존 리소스 receipt에 보존한다.
- 작아지고 품질/호환성 검사를 통과한 후보만 채택한다. 손실 후보 기본 하한은 보이는 RGB PSNR 38dB 이상, 검정/흰색 합성 후 채널당 최대 오차 48/255 이하다. 알파·크기는 항상 동일해야 한다. `--min-psnr`(30–60), `--max-error`(1–64)는 명시적으로만 조정하며 1MB에 맞추려고 자동 완화하지 않는다.
- 도구는 아트 메타데이터나 source/atlas 해시를 자동 갱신하지 않는다. 채택 후 원본·파생본 해시와 변환 설정을 해당 receipt에 반영하고, 제작 시트는 기존 영역·배율로 재구성한 프레임도 비교한다. 픽셀/지표 검사와 실제 게임 렌더링 검사는 구분한다.

## 디코드 메모리·가져오기·출하 확인

- 원본 PNG/음원 크기와 디코드 메모리는 다르다. 256×256 RGBA8 여섯 프레임은 밉맵·드라이버 비용 전 1.5MiB다. 고유 아틀라스의 초기 예산은 soft 96MiB / hard 128MiB이며 측정 결과로 판단한다.
- 필요한 정체성만 지연 로드하고 사용이 끝난 참조를 안전하게 해제하는 정책을 마련한다. 장시간 플레이·장면 전환·도감·죽음 효과까지 포함해 GPU/RSS 최고치를 확인한다. 압축 파일 크기만으로 모바일 성능을 주장하지 않는다.
- 해상도를 줄일 때 원본을 보존하고 layout·기준점·가독성을 함께 검증한다. 불필요한 밉맵·중복 원본·미사용 후보를 런타임 export에 포함하지 않는다.
- `.import` 설정과 실제 Godot 가져오기 결과를 확인하고 `export_presets.cfg`의 포함/제외 및 라이선스를 점검한다. 인덱스에만 등록하거나 에디터에서만 보이는 리소스를 완료로 처리하지 않는다.
- 완료 기준은 실제 파일 존재 → 출처·정체성 확인 → 가져오기/프레임 검사 → 런타임 연결 → 이미지/청감 확인 → 해당 플랫폼 검증이다. 미실행 단계는 [REMAINING](REMAINING.md)에 남긴다.

## 런타임 텍스처 수명

초상화·대체 계열 아틀라스·고유 아틀라스는 실제 표시 요청 때 읽습니다. 전투 화면은 그릴 때 현재 용병·적 정체성을 캐시에 알려 표시 중인 텍스처를 유지합니다. 퇴장한 고유 텍스처는 최근 사용 순으로 정리하며 활성 텍스처 외에 최대 12MiB의 재사용 여유를 둡니다. 전체 soft 목표는 96MiB이고 활성 집합만 이를 넘으면 화질·표시를 보존합니다. 128MiB는 초과 관측 기준이며 강제 해제 상한이 아닙니다. 초상 캐시는 8MiB 목표를 쓰되 활성 개체는 유지합니다.

예산은 PNG/WebP 압축 파일 크기가 아니라 밉맵 없는 RGBA8 디코드 추정치입니다. 실제 GPU·드라이버·브라우저 최고 사용량과는 다릅니다. 캐시 해제는 캐시의 소유 참조만 제거하므로 도감 TextureRect나 호출자가 보유한 프레임은 계속 유효합니다. 리소스 준비 상태를 조회할 때는 메타데이터만 검사하며 전체 텍스처를 로드하지 않습니다.
