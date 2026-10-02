# 정투영·Web 검증 · 2026-10-03 (한국시간)

Godot `4.7.2.stable.official.ed1daf0bf` 표준판으로 검사했다. 기존 4.4.1 Android·밸런스 기록은 [이전 검증](QA_ACCEPTANCE.md)에 보존한다. 이번 변경은 시뮬레이션·저장 스키마·밸런스 데이터를 바꾸지 않는다.

## 구현 및 검수 기준

- 원본 `docs/screenshots/contact_sheet.jpg`는 화면 구성·아트 기준이다. 기능은 최신 스펙과 후속 사용자 지시를 우선한다.
- 전장 원화가 세로 화면 전체를 채우고 HUD·소환·하단 버튼은 그 위에 표시한다. 건물·기물도 소실점 없는 정투영 원화다.
- 36칸 모두 논리 화면에서 86×86픽셀이다. 전역 시작점 (102,354), 전체 516×516. 화면 확대·축소도 두 축에 같은 배율을 사용한다.
- `♥ × 목숨`, 단일 `×1·×2·×3·×5`, 방어력 표기 없음, 용병만 조합, 특수몬스터는 적, 100웨이브 마왕 및 정확히 50번째 적의 즉시 패배를 유지한다.
- 팝업 위로 끝나는 드래그를 취소한다. 이전 구현에서 포인터를 잡은 전장이 팝업 뒤로 용병을 이동시키던 문제를 마우스·터치 회귀 검사로 확인했다.
- Web에서 네모로 보이던 ⚔·◈·✦·Ⅱ는 명시적인 DejaVu Sans fallback으로 고쳤다. 폰트 라이선스도 배포 파일에 포함한다.

## 실행한 검증

| 검사 | 결과 |
|---|---|
| `VERIFY_VISUAL=1 bash scripts/mvp-check.sh` | exit 0, import·규칙/저장/아트 29개·main 300회·UI/좌표/입력 183개 통과 |
| `VERIFY_VISUAL=1 bash scripts/verify.sh` | exit 0, 기존 클라우드 진입점의 29개 검사와 AUTOMATION_PASS·smoke·120 PNG 생성 |
| `bash scripts/web-setup.sh` | 공식 SHA-512 확인, 동일한 4.7.2 엔진과 no-thread Web 템플릿 설치 |
| `bash scripts/web-export.sh` | exit 0, release HTML/JS/WASM/PCK 생성, 필요한 JSON·원화·UI·글꼴 포함 |
| `npm ci --prefix tools/web` 및 `node tools/web/browser-qa.cjs ...` | Playwright 1.57.0 / Chromium 151.0.7922.173, 12개 검사 그룹 통과, 브라우저 오류 0 |

브라우저 검사는 실제 마우스로 시작·3회 소환·선택 해제·재배치·창 열기/닫기를 수행한다. 정지 중 게임시간과 전체 배속 순환을 확인하며 저장→메뉴→이어하기 및 페이지 새로고침 뒤 골드·목숨·웨이브·시간·배속·각 용병 필드를 비교한다. 360×640 터치 입력과 1280×800 레터박스 입력을 확인했다. 일반 URL에는 QA 브리지가 없으며 `?qa=1`은 별도 저장소를 사용한다.

Godot의 네이티브 메뉴·전장·업그레이드·도감·조합·특수·도박·설정 PNG와 최종 Web 전장·모바일·가로 창·일반 메뉴 PNG를 이미지 도구로 확인했다. 자동 PNG 비단색 검사와 이 시각 검수를 구분한다. 사람이 휴대폰을 직접 플레이했다는 뜻은 아니다. Godot 4.7의 ScrollContainer 내부 장식 TextureRect 2개가 기존 원화 검사에 섞이는 것을 확인해, 실제 이름을 붙인 34개 원화만 검사하되 개수 단언을 추가했다.

최종 Web 증거는 `artifacts/web-qa-final-20261002T1511Z/report.json`과 같은 폴더의 PNG 9장이다. 로그는 `artifacts/logs/ortho-final-mvp.log`, `ortho-final-verify.log`, `web-import.log`, `web-export.log`에 있다. 사용자 요청에 따라 새 스크린샷은 저장소에 추가하지 않는다. 검사한 소스 체크섬은 [목록](qa/orthographic-source-sha256.txt)에 기록한다.

- PCK SHA-256: `77ebe37b97e4c08738a8aee361d4985c46252298af30c371c33768f8bcb2d2a8`
- WASM SHA-256: `fc74679e3b97f76878947fcd4fbe1268cbfa6188182a2e33bbc3f5dc9bfa57d0`

## 배포와 남은 검증

첫 GitHub 실행기 검사에서 `rg: command not found`로 중단되어 워크플로에 `ripgrep` 설치를 추가했다. 검사 스크립트도 의존성이 없으면 실행 전 실패하도록 바꿨다. 수정 후 로컬 `bash scripts/mvp-check.sh`는 import·29개 규칙 검사·smoke를 통과했고, `rg`가 없는 환경에서는 PASS 없이 exit 1로 종료함을 확인했다. 검사 로그 전체를 CI 증거에 포함한다.

Pages 빌드/검사/배포 워크플로는 `.github/workflows/web-preview.yml`이다. 저장소의 Pages가 아직 비활성이고 연결 토큰으로 활성화 요청 시 GitHub가 `403 Resource not accessible by integration`을 반환했다. 일반 워크플로 `GITHUB_TOKEN`도 사이트 최초 활성화를 할 수 없다. 저장소 Settings → Pages → Source를 GitHub Actions로 지정해야 공개 배포를 완료할 수 있다. 공개 URL 접속 성공을 주장하지 않는다.

이번 엔진·UI 변경 이후 Android APK 검증, 물리 Android의 GPU·노치·발열·장시간 플레이, 다른 브라우저 및 실제 음향 검증은 남아 있다. 사람 첫 플레이 통계도 아직 없으며 5% 클리어 목표는 유지한다. 출시 제목·소개·스토리·사운드는 [남은 항목](REMAINING.md)에 정리한다.

아트와 Web 작업은 기존 `gpt-6-luna`/`medium` 작업자에게 위임했고, 상태·저장·입력 독립 리뷰는 `gpt-6.1-sol`/`high` 작업자가 수행했다. 최대 동시 작업자는 2명이다. 실제 모델·effort 및 전체 사용량/비용은 제공되지 않아 알 수 없다. 이미지 도구도 구체적 모델 ID를 노출하지 않으므로 최상위 모델 검증을 주장하지 않는다.
