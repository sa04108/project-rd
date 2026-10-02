#!/usr/bin/env node
'use strict';

const fs = require('node:fs');
const path = require('node:path');
const zlib = require('node:zlib');
const playwright = require('playwright');
const { chromium } = playwright;

function parseArgs(argv) {
  const values = { baseUrl: 'http://127.0.0.1:4173/', output: 'artifacts/web-qa', timeout: 20000, bootTimeout: 120000 };
  for (let i = 2; i < argv.length; i += 1) {
    if (argv[i] === '--base-url') values.baseUrl = argv[++i];
    else if (argv[i] === '--output') values.output = argv[++i];
    else if (argv[i] === '--timeout') values.timeout = Number(argv[++i]);
    else if (argv[i] === '--boot-timeout') values.bootTimeout = Number(argv[++i]);
    else throw new Error(`Unknown argument: ${argv[i]}`);
  }
  return values;
}

function readBridgeScript() {
  return `(() => {
    const b = window.__projectRdQa;
    return typeof b === 'function' ? b() : b;
  })()`;
}

async function state(page) {
  return page.evaluate(readBridgeScript());
}

function canonical(value) {
  if (Array.isArray(value)) return value.map(canonical);
  if (value && typeof value === 'object') {
    return Object.fromEntries(Object.keys(value).sort().map(key => [key, canonical(value[key])]));
  }
  return value;
}

async function waitFor(page, predicate, timeout, label) {
  const deadline = Date.now() + timeout;
  let last;
  while (Date.now() < deadline) {
    try {
      last = await state(page);
      if (last && predicate(last)) return last;
    } catch (_) {
      // WebAssembly 게임이 부팅되는 동안 QA 브리지가 잠시 없을 수 있습니다.
    }
    await page.waitForTimeout(250);
  }
  throw new Error(`Timed out waiting for ${label}; last bridge state: ${JSON.stringify(last)}`);
}

async function clickLogical(page, x, y) {
  const frame = await state(page);
  const logicalWidth = Number(frame.frame_size?.[0] || 720);
  const logicalHeight = Number(frame.frame_size?.[1] || 1280);
  await clickAtLogical(page, x, y, logicalWidth, logicalHeight);
}

async function clickAtLogical(page, x, y, logicalWidth, logicalHeight) {
  const canvas = page.locator('canvas').first();
  const rect = await canvas.boundingBox();
  if (!rect) throw new Error('Godot canvas has no visible browser rectangle');
  const point = logicalToScreen(rect, x, y, logicalWidth, logicalHeight);
  await page.mouse.click(point.x, point.y);
}

async function tapLogical(page, x, y) {
  const frame = await state(page);
  const logicalWidth = Number(frame.frame_size?.[0] || 720);
  const logicalHeight = Number(frame.frame_size?.[1] || 1280);
  const canvas = page.locator('canvas').first();
  const rect = await canvas.boundingBox();
  if (!rect) throw new Error('Godot canvas has no visible browser rectangle');
  const point = logicalToScreen(rect, x, y, logicalWidth, logicalHeight);
  await page.touchscreen.tap(point.x, point.y);
}

function logicalToScreen(rect, x, y, logicalWidth, logicalHeight) {
  const scale = Math.min(rect.width / logicalWidth, rect.height / logicalHeight);
  return {
    x: rect.x + (rect.width - logicalWidth * scale) / 2 + x * scale,
    y: rect.y + (rect.height - logicalHeight * scale) / 2 + y * scale,
  };
}

function fittedCanvasBounds(rect, logicalWidth, logicalHeight) {
  const scale = Math.min(rect.width / logicalWidth, rect.height / logicalHeight);
  const width = logicalWidth * scale;
  const height = logicalHeight * scale;
  return { x: rect.x + (rect.width - width) / 2, y: rect.y + (rect.height - height) / 2, width, height };
}

async function clickButton(page, name, useTouch = false) {
  const current = await state(page);
  const button = current?.buttons?.[name];
  if (!button) throw new Error(`Bridge does not expose visible action ${name}`);
  if (button.disabled) throw new Error(`Action ${name} is disabled`);
  const x = button.x + button.width / 2;
  const y = button.y + button.height / 2;
  if (useTouch) await tapLogical(page, x, y);
  else await clickLogical(page, x, y);
}

function pngStats(buffer) {
  const signature = Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]);
  if (!buffer.subarray(0, 8).equals(signature)) throw new Error('Screenshot is not a PNG');
  let offset = 8;
  let width = 0;
  let height = 0;
  let bitDepth = 0;
  let colorType = 0;
  const image = [];
  while (offset < buffer.length) {
    const length = buffer.readUInt32BE(offset);
    const type = buffer.toString('ascii', offset + 4, offset + 8);
    const data = buffer.subarray(offset + 8, offset + 8 + length);
    if (type === 'IHDR') {
      width = data.readUInt32BE(0);
      height = data.readUInt32BE(4);
      bitDepth = data[8];
      colorType = data[9];
    } else if (type === 'IDAT') image.push(data);
    offset += 12 + length;
    if (type === 'IEND') break;
  }
  const channels = colorType === 2 ? 3 : colorType === 6 ? 4 : 0;
  if (bitDepth !== 8 || !channels) throw new Error(`Unsupported screenshot PNG format: depth=${bitDepth}, type=${colorType}`);
  const stride = width * channels;
  const raw = zlib.inflateSync(Buffer.concat(image));
  const pixels = Buffer.alloc(stride * height);
  let source = 0;
  for (let row = 0; row < height; row += 1) {
    const filter = raw[source++];
    const rowStart = row * stride;
    for (let col = 0; col < stride; col += 1) {
      const value = raw[source++];
      const left = col >= channels ? pixels[rowStart + col - channels] : 0;
      const up = row ? pixels[rowStart + col - stride] : 0;
      const upperLeft = row && col >= channels ? pixels[rowStart + col - stride - channels] : 0;
      let predictor = 0;
      if (filter === 1) predictor = left;
      else if (filter === 2) predictor = up;
      else if (filter === 3) predictor = Math.floor((left + up) / 2);
      else if (filter === 4) {
        const p = left + up - upperLeft;
        const pa = Math.abs(p - left);
        const pb = Math.abs(p - up);
        const pc = Math.abs(p - upperLeft);
        predictor = pa <= pb && pa <= pc ? left : pb <= pc ? up : upperLeft;
      } else if (filter !== 0) throw new Error(`Unsupported PNG filter ${filter}`);
      pixels[rowStart + col] = (value + predictor) & 255;
    }
  }
  const colors = new Set();
  let min = 255;
  let max = 0;
  const sampleStep = Math.max(channels, Math.floor(stride * height / 50000 / channels) * channels);
  for (let i = 0; i < pixels.length; i += sampleStep) {
    const rgb = `${pixels[i]},${pixels[i + 1]},${pixels[i + 2]}`;
    colors.add(rgb);
    min = Math.min(min, pixels[i], pixels[i + 1], pixels[i + 2]);
    max = Math.max(max, pixels[i], pixels[i + 1], pixels[i + 2]);
  }
  return { width, height, unique_sampled_rgb: colors.size, sampled_channel_min: min, sampled_channel_max: max };
}

async function capture(page, outDir, name) {
  const file = path.join(outDir, `${name}.png`);
  const png = await page.screenshot({ path: file, fullPage: false });
  const stats = pngStats(png);
  if (stats.unique_sampled_rgb < 12 || stats.sampled_channel_max - stats.sampled_channel_min < 32) {
    throw new Error(`${name} screenshot appears blank or flat: ${JSON.stringify(stats)}`);
  }
  return { file, ...stats };
}

async function captureWhenRendered(page, outDir, name, timeout) {
  const deadline = Date.now() + timeout;
  let lastError;
  while (Date.now() < deadline) {
    try {
      return await capture(page, outDir, name);
    } catch (error) {
      if (!String(error.message).includes('appears blank or flat')) throw error;
      lastError = error;
      await page.waitForTimeout(500);
    }
  }
  throw lastError || new Error(`${name} did not render before timeout`);
}

async function main() {
  const options = parseArgs(process.argv);
  const outDir = path.resolve(options.output);
  fs.mkdirSync(outDir, { recursive: true });
  const browser = await chromium.launch({
    headless: true,
    executablePath: process.env.CHROMIUM_PATH || (fs.existsSync('/usr/bin/chromium') ? '/usr/bin/chromium' : undefined),
    args: ['--no-sandbox', '--enable-webgl', '--ignore-gpu-blocklist', '--use-gl=angle', '--use-angle=swiftshader'],
  });
  const failures = [];
  const captures = [];
  const context = await browser.newContext({ viewport: { width: 720, height: 1280 }, deviceScaleFactor: 1, hasTouch: true });
  const page = await context.newPage();
  page.on('pageerror', error => failures.push(`pageerror: ${error.message}`));
  page.on('console', message => {
    if (message.type() === 'error') failures.push(`console: ${message.text()}`);
  });

  try {
    await page.goto(`${options.baseUrl}${options.baseUrl.includes('?') ? '&' : '?'}qa=1`, { waitUntil: 'domcontentloaded', timeout: options.bootTimeout });
    const menu = await waitFor(page, s => s.android_qa === false && s.mode && s.buttons, options.bootTimeout, 'QA bridge and menu');
    if (!menu.art_ready) throw new Error('Art readiness flag is false at initial menu');
    if (await page.evaluate(() => typeof window.__projectRdQa === 'undefined')) throw new Error('QA bridge was not exposed on ?qa=1');
    if (!(menu.frame_size?.[0] > 0 && menu.frame_size?.[1] > 0)) throw new Error(`Invalid logical frame size: ${JSON.stringify(menu.frame_size)}`);
    captures.push(await capture(page, outDir, 'menu'));

    await clickButton(page, 'new_game');
    let current = await waitFor(page, s => s.buttons?.confirm_new || s.mode === 'battle', options.timeout, 'new game confirmation or battle');
    if (current.buttons?.confirm_new) await clickButton(page, 'confirm_new');
    let battle = await waitFor(page, s => s.mode === 'battle' || s.panel_name === 'battle', options.timeout, 'new battle');
    if (battle.units.length !== 0) throw new Error(`Expected new run with no units, got ${battle.units.length}`);

    for (let i = 0; i < 3; i += 1) {
      const before = (await state(page)).units.length;
      await clickButton(page, 'summon');
      await waitFor(page, s => s.units?.length > before, options.timeout, `summon ${i + 1}`);
    }
    captures.push(await capture(page, outDir, 'battle-after-summon'));
    if (battle.speed !== 1) throw new Error(`A new run should start at speed 1, got ${battle.speed}`);
    await clickButton(page, 'pause');
    current = await waitFor(page, s => Object.keys(s.pause_reasons || {}).length > 0, options.timeout, 'paused state');
    const pausedTime = current.time;
    for (const expectedSpeed of [2, 3, 5, 1]) {
      await clickButton(page, 'speed');
      current = await waitFor(page, s => s.speed === expectedSpeed, options.timeout, `speed ${expectedSpeed}`);
      if (Math.abs(current.time - pausedTime) > 0.01) throw new Error('Game time advanced while paused during speed cycling');
    }
    await clickButton(page, 'pause');
    await waitFor(page, s => Object.keys(s.pause_reasons || {}).length === 0, options.timeout, 'unpaused state');

    let unitsBeforeMove = (await state(page)).units;
    let selectedId = (await state(page)).selected;
    if (selectedId >= 0) {
      const selectedUnit = unitsBeforeMove.find(unit => unit.id === selectedId);
      if (!selectedUnit) throw new Error(`Selected unit ${selectedId} is absent from the unit list`);
      const cells = (await state(page)).cell_centers;
      const selectedCell = cells.find(cell => cell.cell === selectedUnit.cell);
      if (!selectedCell) throw new Error(`Selected unit cell ${selectedUnit.cell} has no input coordinate`);
      await clickLogical(page, selectedCell.x, selectedCell.y);
      await waitFor(page, s => s.selected === -1, options.timeout, 'clear initial unit selection');
    }
    unitsBeforeMove = (await state(page)).units;
    const first = unitsBeforeMove[0];
    const occupied = new Set(unitsBeforeMove.map(unit => unit.cell));
    const targetCell = (await state(page)).cell_centers?.find(cell => !occupied.has(cell.cell));
    if (first && targetCell) {
      const cells = await state(page).then(s => s.cell_centers);
      const source = cells.find(cell => cell.cell === first.cell);
      if (!source) throw new Error(`No coordinate for occupied cell ${first.cell}`);
      await clickLogical(page, source.x, source.y);
      await waitFor(page, s => s.selected === first.id, options.timeout, 'select unit for relocation');
      await clickLogical(page, targetCell.x, targetCell.y);
      await waitFor(page, s => s.units?.some(unit => unit.id === first.id && unit.cell === targetCell.cell), options.timeout, 'unit relocation');
    }

    for (const panel of ['guide', 'codex', 'recipes']) {
      const oldPanel = (await state(page)).panel_name;
      await clickButton(page, panel);
      await waitFor(page, s => s.panel_name && s.panel_name !== oldPanel, options.timeout, `${panel} panel`);
      if (panel === 'recipes') captures.push(await capture(page, outDir, 'recipes'));
      await clickButton(page, 'close_panel');
      await waitFor(page, s => !s.panel_name || s.panel_name === 'battle', options.timeout, `close ${panel}`);
    }

    await clickButton(page, 'settings');
    await waitFor(page, s => Object.keys(s.pause_reasons || {}).length > 0, options.timeout, 'settings pause');
    await clickButton(page, 'save_menu');
    const menuAfterSave = await waitFor(page, s => s.mode === 'menu', options.timeout, 'save and return to menu');
    if (!menuAfterSave.snapshot_exists || menuAfterSave.save_error) throw new Error(`Save failed: ${menuAfterSave.save_error}`);
    const saved = {
      gold: menuAfterSave.gold,
      lives: menuAfterSave.lives,
      wave: menuAfterSave.wave,
      time: menuAfterSave.time,
      units: canonical(menuAfterSave.units),
      speed: menuAfterSave.speed,
    };
    await clickButton(page, 'continue');
    let resumed = await waitFor(page, s => s.mode === 'battle', options.timeout, 'continue saved game');
    if (resumed.gold !== saved.gold || resumed.units.length !== saved.units.length || Math.abs(resumed.time - saved.time) > 0.01 || resumed.speed !== saved.speed) {
      throw new Error('Continue did not restore saved gold, units, time, and speed');
    }
    if (Object.keys(resumed.pause_reasons || {}).length === 0) throw new Error('Continue should restore the run paused');
    if (JSON.stringify(canonical(resumed.units)) !== JSON.stringify(saved.units)) throw new Error('Continue did not restore every unit field');
    captures.push(await capture(page, outDir, 'resumed'));

    const oldSession = resumed.session_id;
    await page.reload({ waitUntil: 'domcontentloaded', timeout: options.timeout });
    const restartedMenu = await waitFor(page, s => s.mode === 'menu' && s.session_id !== oldSession, options.timeout, 'fresh browser session');
    if (!restartedMenu.snapshot_exists) throw new Error('Browser reload lost the saved snapshot');
    await clickButton(page, 'continue');
    resumed = await waitFor(page, s => s.mode === 'battle', options.timeout, 'resume after browser reload');
    if (resumed.gold !== saved.gold || resumed.lives !== saved.lives || resumed.wave !== saved.wave || resumed.units.length !== saved.units.length || Math.abs(resumed.time - saved.time) > 0.01 || resumed.speed !== saved.speed) {
      throw new Error('Browser reload resume did not restore the saved run fields');
    }
    if (Object.keys(resumed.pause_reasons || {}).length === 0) throw new Error('Browser reload resume should remain paused');
    if (JSON.stringify(canonical(resumed.units)) !== JSON.stringify(saved.units)) throw new Error('Browser reload did not restore every unit field');
    captures.push(await capture(page, outDir, 'browser-restart'));

    await clickButton(page, 'pause');
    await waitFor(page, s => Object.keys(s.pause_reasons || {}).length === 0, options.timeout, 'unpause restored run before touch test');
    await page.setViewportSize({ width: 360, height: 640 });
    await page.waitForTimeout(300);
    await clickButton(page, 'pause', true);
    current = await waitFor(page, s => Object.keys(s.pause_reasons || {}).length > 0, options.timeout, 'mobile viewport pause input');
    captures.push(await capture(page, outDir, 'mobile-resumed'));
    await page.waitForTimeout(500);
    if (Math.abs((await state(page)).time - current.time) > 0.01) throw new Error('Game time advanced while paused at mobile viewport');
    await clickButton(page, 'pause', true);
    await waitFor(page, s => Object.keys(s.pause_reasons || {}).length === 0, options.timeout, 'mobile viewport unpause input');

    await page.setViewportSize({ width: 1280, height: 800 });
    await page.waitForTimeout(300);
    const wideFrame = await state(page);
    const wideCanvas = await page.locator('canvas').first().boundingBox();
    captures.push({ ...(await capture(page, outDir, 'wide-viewport-layout')), frame_size: wideFrame.frame_size, canvas_bounds: wideCanvas, fitted_canvas_bounds: fittedCanvasBounds(wideCanvas, wideFrame.frame_size[0], wideFrame.frame_size[1]) });
    await clickButton(page, 'pause');
    await waitFor(page, s => Object.keys(s.pause_reasons || {}).length > 0, options.timeout, 'wide viewport pause input');
    captures.push(await capture(page, outDir, 'wide-viewport'));
    await clickButton(page, 'pause');
    await waitFor(page, s => Object.keys(s.pause_reasons || {}).length === 0, options.timeout, 'wide viewport unpause input');

    const plainPage = await browser.newPage({ viewport: { width: 720, height: 1280 } });
    plainPage.on('pageerror', error => failures.push(`public pageerror: ${error.message}`));
    plainPage.on('console', message => {
      if (message.type() === 'error') failures.push(`public console: ${message.text()}`);
    });
    await plainPage.goto(options.baseUrl, { waitUntil: 'domcontentloaded', timeout: options.bootTimeout });
    await plainPage.waitForFunction(() => {
      const canvas = document.querySelector('canvas');
      return canvas && canvas.width > 0 && canvas.height > 0;
    }, null, { timeout: options.bootTimeout });
    captures.push(await captureWhenRendered(plainPage, outDir, 'public-normal', Math.min(options.bootTimeout, 30000)));
    if (await plainPage.evaluate(() => typeof window.__projectRdQa !== 'undefined')) throw new Error('QA bridge is visible without ?qa=1');
    await plainPage.close();

    if (failures.length) throw new Error(`Browser runtime errors: ${failures.join('\n')}`);
    const report = {
      result: 'pass',
      run_id: new Date().toISOString().replaceAll(':', '').replaceAll('-', ''),
      base_url: options.baseUrl,
      browser: 'Chromium via Playwright',
      browser_version: browser.version(),
      playwright_version: require('playwright/package.json').version,
      checks: ['QA bridge gated by query flag', 'initial art and frame ready', 'new run and three summons', 'pause freezes simulation', 'speed cycle 1→2→3→5→1', 'unit relocation', 'guide/codex/recipe panels', 'save-menu-continue', 'browser reload and persistent restore', 'desktop, mobile-touch, and wide viewport input', 'public URL omits QA bridge', 'all screenshots contain visible pixel diversity'],
      final_state: resumed,
      screenshots: captures,
      browser_errors: failures,
    };
    fs.writeFileSync(path.join(outDir, 'report.json'), `${JSON.stringify(report, null, 2)}\n`);
    process.stdout.write(`${JSON.stringify(report, null, 2)}\n`);
  } catch (error) {
    const report = { result: 'fail', error: error.stack || String(error), browser_errors: failures, screenshots: captures };
    fs.writeFileSync(path.join(outDir, 'report.json'), `${JSON.stringify(report, null, 2)}\n`);
    process.stderr.write(`${JSON.stringify(report, null, 2)}\n`);
    process.exitCode = 1;
  } finally {
    await browser.close();
  }
}

main().catch(error => {
  process.stderr.write(`${error.stack || error}\n`);
  process.exitCode = 1;
});
