# Web preview and browser QA

각 브랜치의 push는 Web 빌드와 브라우저 검사를 실행합니다. `main`의 push와 명시적인 `workflow_dispatch` 실행은 검사가 통과하면 해당 실행의 산출물을 GitHub Pages에 배포합니다. 다른 브랜치의 push는 검사와 산출물 보관만 수행합니다. 워크플로는 브랜치를 병합하거나 `main`을 변경하지 않습니다.

The export uses the pinned Godot version from `.godot-version` and the official `web_nothreads` templates. `scripts/web-setup.sh` verifies release assets against Godot's published SHA-512 list before installing them. It uses the existing verified cache at `/workspace/.tools/godot-4.7.2-downloads` when present, or stores verified downloads beneath `.godot-tools/` otherwise. Exported files and the Godot user cache stay under ignored `artifacts/` paths.

## Local export and preview

```bash
bash scripts/web-setup.sh
bash scripts/web-export.sh
python3 scripts/web-serve.py --directory artifacts/web
```

Open `http://127.0.0.1:4173/` for ordinary play. To run the automated browser checks, install the pinned test dependency and Chromium once:

```bash
npm ci --prefix tools/web
tools/web/node_modules/.bin/playwright install chromium
```

In another terminal, run the QA URL and preserve its screenshots/report under ignored artifacts:

```bash
node tools/web/browser-qa.cjs --base-url 'http://127.0.0.1:4173/' --output artifacts/web-qa
```

The test opens the debug bridge only with `?qa=1`, then uses real browser mouse events on the Godot canvas. The bridge reports logical 720×1280 button rectangles and board-cell centers; the test maps these through the actual browser canvas bounds. It checks a new run, summons, pause-time stability, the full ×1/×2/×3/×5 cycle, unit movement, help/catalog/recipe panels, save and continue, browser reload persistence, desktop and mobile viewport input, and confirms that a normal URL does not expose the bridge. Screenshots have a pixel-diversity check so a blank canvas cannot pass based only on game-state values.

저장 검사는 메뉴에 표시된 파일의 존재만으로 완료를 판단하지 않습니다. 실제 IndexedDB의 QA `run.json`과 `profile.json`이 방금 저장한 전체 값과 일치할 때까지 최대 20초 동안 읽기 전용으로 관측합니다. 동기화를 강제하지 않으며, 기록이 확정되지 않으면 검사에 실패합니다. 그 뒤 새로고침한 게임이 읽은 전체 스냅샷·프로필과 복원된 전투 상태를 각각 비교합니다. 이 검증은 기록 확정 후의 복원을 확인하며, 저장 직후 페이지를 즉시 닫아도 된다는 보장은 아닙니다. 자세한 회귀 검증은 [WEB_SAVE_RELOAD_QA.md](WEB_SAVE_RELOAD_QA.md)에 기록합니다.

Playwright can use its installed Chromium or `/usr/bin/chromium`; set `CHROMIUM_PATH` to select a different local binary. The test serves the export over HTTP because browsers do not load the WebAssembly build correctly from `file://` URLs. Thread support stays disabled, so the preview does not require cross-origin isolation headers.

## Pages workflow

`.github/workflows/web-preview.yml`은 모든 브랜치 push에서 고정된 Godot 및 템플릿을 설치하고 Web 빌드와 Playwright 검사를 실행합니다. 상대 경로 asset을 사용하므로 프로젝트 Pages 하위 경로에서도 동작합니다. `main` push는 검사가 통과하면 Pages에 배포합니다. 수동 `workflow_dispatch`는 선택한 ref의 검사가 통과하면 해당 산출물을 배포합니다. 다른 브랜치의 일반 push는 배포하지 않습니다.

배포 작업은 빌드와 브라우저 검사가 성공한 뒤에만 실행됩니다. 빌드 권한은 `contents: read`, 배포 권한은 `pages: write`와 `id-token: write`로 제한했습니다. 저장소 secret은 필요하지 않습니다. Pages 배포를 처음 사용하기 전에 **Settings → Pages**에서 배포 source를 **GitHub Actions**로 지정해야 합니다. 워크플로의 `GITHUB_TOKEN`으로는 이 저장소 설정을 변경할 수 없습니다.

브라우저 자동 검사의 대상은 Playwright가 설치한 Chromium입니다. 다른 브라우저나 기기 전반의 호환성을 의미하지는 않습니다.

## 이전 로컬 검증 스냅샷

The Godot 4.7.2 Web export completed and passed browser QA on 2026-10-03 (KST). Playwright 1.57.0 with Chromium 151.0.7922.173 passed all 12 checks, including Korean UI/glyph rendering, touch input at 360×640, desktop input at 720×1280, letterboxed input at 1280×800, pause and speed controls, and save/restore after browser reload. The report and nine screenshots are under `artifacts/web-qa-final-20261002T1511Z/`.

당시 `index.pck` SHA-256은 `77ebe37b97e4c08738a8aee361d4985c46252298af30c371c33768f8bcb2d2a8`, `index.wasm`은 `fc74679e3b97f76878947fcd4fbe1268cbfa6188182a2e33bbc3f5dc9bfa57d0`이다. 이는 로컬 내보내기와 브라우저 검사 기록이다. 공개 배포 성공은 해당 Actions 배포 결과와 실제 URL로 별도 확인해야 한다. 첫 배포 전에 **Settings → Pages → GitHub Actions**를 지정해야 한다.
