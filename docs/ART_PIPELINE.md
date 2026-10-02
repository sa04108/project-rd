# Sprite art pipeline

Character animation is produced through the documented [`aldegad/sprite-gen`](https://github.com/aldegad/sprite-gen) run format and extraction/composition commands. The conversation `image_gen__imagegen` tool generated source art from the run's prepared prompts and layout guides; sprite-gen's own Codex adapter was not used. The game consumes transparent family atlases and their runtime `manifest.json.frame_layout` files, and does not draw replacement character parts.

## Runtime coverage

`tools/art/build_manifest.py` reads the source catalogs and writes all 87 identities: 34 units, 40 normal enemies, 10 bosses, and 3 special enemies. Each identity maps explicitly to one of seven shared family atlases: humanoid, heavy, quadruped, multi, floating, blob, or dragon. Per-entry tint and catalog identity remain planned identity metadata; they do not count as unique character art. All 87 distinct portraits are installed. The codex uses each identity’s portrait; the 34 battlefield allies also use these individual textures with whole-image breathing/attack translation. Enemies use the seven family frame animations with per-entry tint. Individual enemy frame animation for all 53 identities is still shared, not unique.

Every family atlas uses 256×256 RGBA frames and provides six frames each for idle, walk, and attack. Runtime files live at `assets/art/families/<family>/sprite-sheet-alpha.png` and `assets/art/families/<family>/manifest.json`. Raw prompts, references, and generated rows remain in `sprite_run/`, which contains `.gdignore` so Godot will not import or export the large source work files.

The manifest distinguishes planned catalog entries, generated atlases, sprite-gen automatic checks, and recorded visual inspection. All visual inspection in this task was performed by coding agents using image-viewing tools; no human review is claimed. The receipt field retains the legacy name `human_visual_review`, but its reviewed notes describe that agent inspection. Automated reports do not certify visual review. All seven final atlases were visually inspected after extraction. Quadruped and dragon rows were re-extracted with component segmentation to remove visible boundary fragments; the blob attack row was regenerated without the detached flame. No detached artifacts remained in the final reviewed sheets. The humanoid idle row remains nearly static and retains sprite-gen's low-motion warning (score 95). Blob's final attack report still records 28 edge pixels (score 99); its replacement pseudopod is visibly attached, and that warning remains recorded. Individual review notes are stored in each family's `pipeline-receipt.json`. The aggregate manifest retains humanoid as `generated_unreviewed`; the other six have `auto_checks_passed` status. Visual inspection notes remain separate from those generated statuses.

Environment art is tracked separately. `assets/art/backgrounds/guild.png` is the menu background and `assets/art/orthographic/battle-map.png` is the current full-screen orthographic battle background. The former `assets/art/backgrounds/battlefield.png` is retained as historical source art and is no longer rendered. Their presence is recorded as generated, not as per-entry character coverage.

## Generate and import a family

The external tool is pinned to sprite-gen `v2.17.0` / commit `4a2ebdbcbb9e228b143ef10876ecd48261288df0`, installed outside the game checkout at `/workspace/.tools/sprite-gen`; its interpreter is `/workspace/.tools/sprite-gen/.venv/bin/sprite-gen`.

1. Prepare the run with the selected base art, 256×256 cell size, six-frame state definitions, and a flat chroma key. Keep `.gdignore` in the raw run directory.
2. Use sprite-gen's `prompts/<state>.txt` and `references/layout-guides/<state>.png` as the source specification for the row generation tool. Preserve the exact frame count, key color, identity, and state action described there.
3. Extract with `sprite-gen extract --run-dir <run> --segmentation projection` when adjacent generated silhouettes touch; the command reports any DP-forced splits. Compose with `sprite-gen compose-atlas --run-dir <run>`.
4. Run `sprite-gen inspect --run-dir <run> --states idle,walk,attack` and `sprite-gen score --inspect-report <run>/sprite-inspect.report.json`. Review warnings and the sheet visually. Keep the raw reports; never label automatic checks as visual inspection.
5. Import runtime files with `python3 tools/art/import_family.py <family>`. `--allow-unreviewed` is needed only when inspect or score did not pass. The importer validates six frames per state, timing metadata, 256×256 regions, and a transparent RGBA atlas; its receipt records that the image model identifier was not exposed by the conversation tool.
6. Refresh and validate the catalog map:

```bash
python3 tools/art/build_manifest.py
python3 tools/art/validate_manifest.py
```

The manifest does not claim a named highest-tier model: the image-generation tool did not expose a selectable or reported model identifier in this run. Its model tier therefore remains unverified in `pipeline-receipt.json` even though the user authorized this generation route.

## Static identity portraits

Each of the 87 catalog entries also has a distinct identity portrait under `assets/art/portraits/<id>.png`. A 4×4 identity sheet may be split with sprite-gen's canonical extractor:

```bash
/workspace/.tools/sprite-gen/.venv/bin/sprite-gen slice-sheet \
  --sheet <batch.png> --out-dir <batch-output> \
  --chroma-key '#FF00FF' --grid 4x4 --names <16 comma-separated IDs> \
  --cell-width 384 --cell-height 256 --baseline-y 236 --target-height 208
```

Batch receipts must record the IDs in reading order, exact prompts, source PNG, and extraction report. Do not count an ID until its individual extracted file exists and passes the extraction checks. Distinct per-entry portraits are tracked separately from shared animated family sheets.

All six source sheets were visually inspected. `tools/art/portrait_batches/import_batch.py` runs canonical extraction and rejects empty alpha or any canvas-edge contact for every result; the 384-pixel width preserves broad creatures and weapons. Wide/ornate extracted samples were also inspected. Portraits contain full character art; no joint drawing remains in the runtime. Raw batch sheets and exact prompt packets are retained, while duplicate per-batch cutouts and regenerable frame caches are ignored by Git.

## 정투영 전장과 UI

최신 사용자의 정투영 지시에 따라 `assets/art/orthographic/battle-map.png`를 생성했다. 원본 941×1672 PNG와 정확한 프롬프트를 함께 보존한다. 그림에 격자·문구를 굽지 않고 런타임에서 동일한 86×86칸을 그린다. 새 건물·기물은 소실점 없는 탑뷰로 제작했다. 기존 캐릭터 스프라이트와 애니메이션은 재사용하며 새 애니메이션 생성은 수행하지 않았다.

`assets/ui/`의 SVG는 직접 작성한 벡터 장식이다. 금속 테두리·청색 버튼·양피지 패널의 9분할 크기 조절을 지원한다. UI에 등장하는 HP·비용·웨이브 등 문구와 수치는 이미지에 포함하지 않는다. 대화 이미지 도구의 구체적인 모델 식별자는 이번에도 노출되지 않았으며 최상위 모델 검증을 주장하지 않는다.

Web에서 시스템 글꼴에 의존하지 않도록 DejaVu Sans를 `assets/fonts/GuildSymbols.ttf`에 함께 배포한다. 원본 Debian fonts-dejavu-core 저작권·라이선스는 `GuildSymbols-LICENSE.txt`에 보존한다. 기존 한국어 글꼴에 없는 ⚔·◈·✦·Ⅱ를 이 명시적 fallback으로 표시한다.
