# Web preview and browser QA

This feature branch exports the Godot project as a single-threaded Web build and deploys it to GitHub Pages after the browser checks pass. The Pages workflow is scoped to `feat/ortho-reference-web`; it does not merge or update `main`. The branch deployment is public once GitHub Pages is enabled for GitHub Actions and the workflow receives its normal `GITHUB_TOKEN` permissions.

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

Playwright can use its installed Chromium or `/usr/bin/chromium`; set `CHROMIUM_PATH` to select a different local binary. The test serves the export over HTTP because browsers do not load the WebAssembly build correctly from `file://` URLs. Thread support stays disabled, so the preview does not require cross-origin isolation headers.

## Pages workflow

Pushing this branch runs `.github/workflows/web-preview.yml`. It installs the exact pinned Godot release and templates, exports the project, starts the local static server, runs the Playwright browser checks, and uploads the export to the GitHub Pages deployment job. The workflow uses relative output assets, so it works at the project Pages subpath. `workflow_dispatch` can build and test the Web artifact without deploying it.

The deploy job publishes only after the build and browser checks succeed. Its permissions are limited to `contents: read` for build and `pages: write` plus `id-token: write` for the deploy job. No repository secrets are required. Before the first deployment, open **Settings → Pages** and set the build and deployment source to **GitHub Actions**. The workflow cannot change this repository setting with `GITHUB_TOKEN`.

The local QA flow verifies the preview before deployment. It does not claim compatibility across all browsers or devices; Chromium is the automated browser target.

## Local validation snapshot

The Godot 4.7.2 Web export completed and passed browser QA on 2026-10-03 (KST). Playwright 1.57.0 with Chromium 151.0.7922.173 passed all 12 checks, including Korean UI/glyph rendering, touch input at 360×640, desktop input at 720×1280, letterboxed input at 1280×800, pause and speed controls, and save/restore after browser reload. The report and nine screenshots are under `artifacts/web-qa-final-20261002T1511Z/`.

The exported `index.pck` SHA-256 is `77ebe37b97e4c08738a8aee361d4985c46252298af30c371c33768f8bcb2d2a8`; `index.wasm` SHA-256 is `fc74679e3b97f76878947fcd4fbe1268cbfa6188182a2e33bbc3f5dc9bfa57d0`. The public Pages deployment has not yet been enabled or verified. Select **Settings → Pages → GitHub Actions** before the authorized feature-branch push can publish the preview.
