#!/usr/bin/env node
'use strict';

// 격리된 ?qa=1 저장과 실제 캔버스 입력으로 반복 진입·연속 전투를 관측한다.
// 실행 예: WEB_EXPORT_MODE=debug bash scripts/web-export.sh artifacts/web-memory
// python3 scripts/web-serve.py --directory artifacts/web-memory --port 4173
// CHROMIUM_PATH=/usr/bin/chromium node tools/web/memory-soak.cjs --cycles 12 --battle-seconds 30 --endurance-seconds 180
// 빠른 계측 점검: --cycles 4 --warmup-cycles 1 --battle-seconds 10 --endurance-seconds 30
// 브라우저/Godot 메모리를 강제 회수하지 않는다. Wasm capacity는 live allocation이 아니다.
// 정적 메모리·고아 노드의 release 미지원 0은 통과 근거로 사용하지 않는다.
// 공식 모니터 정의: https://docs.godotengine.org/en/stable/classes/class_performance.html
// 결과는 artifacts/ 아래 JSONL(중단 시에도 보존), report.json, 화면 캡처에 남긴다.

const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const { execFileSync } = require('node:child_process');
const { chromium } = require('playwright');
const MiB = 1024 * 1024;

function parseArgs(argv) {
  const result = { baseUrl: 'http://127.0.0.1:4173/', output: 'artifacts/web-memory-soak', cycles: 12, warmupCycles: 3,
    battleSeconds: 30, enduranceSeconds: 180, sampleIntervalMs: 1000, settleMs: 1500, timeout: 20000,
    bootTimeout: 120000, stallMs: 15000, runTimeout: 1800000, allowRelease: false, selfTest: false, musicOff: false };
  const keys = { '--base-url': 'baseUrl', '--output': 'output', '--cycles': 'cycles', '--warmup-cycles': 'warmupCycles',
    '--battle-seconds': 'battleSeconds', '--endurance-seconds': 'enduranceSeconds', '--sample-interval-ms': 'sampleIntervalMs',
    '--settle-ms': 'settleMs', '--timeout': 'timeout', '--boot-timeout': 'bootTimeout', '--stall-ms': 'stallMs', '--run-timeout': 'runTimeout' };
  for (let i = 2; i < argv.length; i++) {
    if (argv[i] === '--music-off') result.musicOff = true;
    else if (argv[i] === '--allow-release') result.allowRelease = true;
    else if (argv[i] === '--self-test') result.selfTest = true;
    else if (keys[argv[i]]) {
      const key = keys[argv[i]], value = argv[++i];
      if (value === undefined) throw new Error(`Missing value for ${argv[i - 1]}`);
      result[key] = typeof result[key] === 'number' ? Number(value) : value;
    } else throw new Error(`Unknown argument: ${argv[i]}`);
  }
  for (const [key, value] of Object.entries(result)) {
    if (typeof value === 'number' && (!Number.isFinite(value) || value < 0)) throw new Error(`Invalid ${key}: ${value}`);
  }
  if (!Number.isInteger(result.cycles) || !Number.isInteger(result.warmupCycles) || result.cycles < result.warmupCycles + 3) {
    throw new Error('Need at least three measured cycles after integer warmup-cycles');
  }
  if (result.sampleIntervalMs < 200 || result.settleMs < 1000 || result.battleSeconds < 1 || result.stallMs < 1000 || result.timeout < 1000) {
    throw new Error('sample-interval-ms >= 200, settle-ms/stall-ms/timeout >= 1000, battle-seconds >= 1 required');
  }
  new URL(result.baseUrl);
  return result;
}

function trend(values) {
  if (!values.length || values.some(v => !Number.isFinite(v))) return { supported: false };
  const count = values.length, meanX = (count - 1) / 2, meanY = values.reduce((a, b) => a + b, 0) / count;
  let numerator = 0, denominator = 0;
  values.forEach((value, index) => { numerator += (index - meanX) * (value - meanY); denominator += (index - meanX) ** 2; });
  return { supported: true, count, first: values[0], last: values.at(-1), min: Math.min(...values), max: Math.max(...values),
    delta: values.at(-1) - values[0], slope_per_cycle: denominator ? numerator / denominator : 0 };
}

function analyze(checkpoints, warmupCycles, debugBuild) {
  const settled = checkpoints.filter(s => s.cycle > warmupCycles);
  const limits = { static_bytes: 8 * MiB, object_count: 64, node_count: 2, orphan_node_count: 0,
    resource_count: 16, texture_bytes: 8 * MiB, buffer_bytes: 2 * MiB, video_bytes: 10 * MiB };
  const metrics = {}, regressions = [];
  for (const [key, tolerance] of Object.entries(limits)) {
    const summary = trend(settled.map(s => s.godot.memory[key]));
    if (!debugBuild && ['static_bytes', 'orphan_node_count'].includes(key)) summary.supported = false;
    if (summary.max === 0 && key.endsWith('_bytes')) summary.supported = false;
    summary.tolerance = tolerance;
    summary.excess_growth = summary.supported && summary.delta > tolerance;
    if (summary.excess_growth) regressions.push(key);
    metrics[key] = summary;
  }
  const browserLifecycle = {};
  for (const [key, read, tolerance] of [
    ['audio_handlers', s => s.browser.cdp_metrics?.AudioHandlers, 32],
    ['dom_nodes', s => s.browser.dom?.nodes, 4],
    ['js_event_listeners', s => s.browser.dom?.jsEventListeners, 8],
  ]) {
    const summary = trend(settled.map(read));
    summary.tolerance = tolerance;
    // 오디오 핸들러·리스너는 GC 시점에 따라 변하므로 참고 추세이며 누수 단언이 아니다.
    summary.diagnostic_only = key !== 'dom_nodes';
    summary.excess_growth = !summary.diagnostic_only && summary.supported && summary.delta > tolerance;
    if (summary.excess_growth) regressions.push(key);
    browserLifecycle[key] = summary;
  }
  const wasm = trend(settled.map(s => s.browser.wasm_capacity_bytes));
  const jsHeap = trend(settled.map(s => s.browser.js_heap_used_bytes));
  const frameRates = settled.map(s => s.frame_interval?.fps).filter(Number.isFinite);
  return { measured_cycles: settled.length, warmup_cycles_excluded: warmupCycles, settled_menu_metrics: metrics,
    browser_lifecycle: browserLifecycle, wasm_capacity: wasm, js_heap_used: jsHeap, sampled_menu_fps: trend(frameRates), regressions,
    interpretation: settled.length < 3 ? 'Insufficient completed settled-menu cycles for a growth comparison; inspect crash/error evidence.'
      : regressions.length ? 'Settled live counters grew beyond tolerances; investigate retained resources/objects. Capacity alone is not proof of a leak.'
      : (!debugBuild ? 'No measured counter exceeded tolerance; release omits live static/orphan evidence, so live-allocation leakage remains unverified.'
        : 'No settled live counter exceeded tolerance in this bounded run. Retained Wasm capacity is allocator high-water capacity, not live allocations.'),
    limitations: ['Bounded deterministic UI workload, not proof against every leak or physical-device crash.',
      'Wasm linear-memory capacity does not shrink; JavaScript heap and process RSS are separate measurements.',
      'Linux RSS sums shared pages more than once; unsupported process counters are null.',
      'SwiftShader frame timing includes software rendering and host load; no forced GC is used.'] };
}

function summarizeSamples(samples) {
  const quantiles = values => {
    const sorted = values.filter(Number.isFinite).sort((a, b) => a - b);
    const at = percentile => sorted.length ? sorted[Math.floor((sorted.length - 1) * percentile)] : null;
    return { count: sorted.length, min: at(0), p10: at(0.1), median: at(0.5), p90: at(0.9), max: at(1) };
  };
  const frameTiming = {};
  for (const phase of [...new Set(samples.map(s => s.phase))]) {
    const matching = samples.filter(s => s.phase === phase && s.frame_interval?.elapsed_ms >= 500);
    frameTiming[phase] = { sampled_fps: quantiles(matching.map(s => s.frame_interval.fps)),
      frames_over_50_msec: matching.reduce((sum, s) => sum + s.frame_interval.frames_over_50_msec, 0) };
  }
  const usage = {};
  for (const key of ['static_bytes', 'static_peak_bytes', 'object_count', 'node_count', 'orphan_node_count', 'resource_count', 'texture_bytes', 'video_bytes']) {
    usage[key] = quantiles(samples.map(s => s.godot.memory[key]));
  }
  usage.wasm_capacity_bytes = quantiles(samples.map(s => s.browser.wasm_capacity_bytes));
  usage.js_heap_used_bytes = quantiles(samples.map(s => s.browser.js_heap_used_bytes));
  usage.audio_handlers = quantiles(samples.map(s => s.browser.cdp_metrics.AudioHandlers));
  usage.audio_worklet_processors = quantiles(samples.map(s => s.browser.cdp_metrics.AudioWorkletProcessors));
  usage.active_audio_sources = quantiles(samples.map(s => s.browser.web_audio?.active_buffer_sources));
  usage.active_long_audio_sources = quantiles(samples.map(s => s.browser.web_audio?.active_long_buffer_sources));
  usage.disconnected_active_audio_sources = quantiles(samples.map(s => s.browser.web_audio?.disconnected_active_sources));
  usage.browser_process_rss_sum_bytes = quantiles(samples.map(s => {
    const values = s.browser.processes.map(p => p.rss_bytes);
    return values.length && values.every(Number.isFinite) ? values.reduce((a, b) => a + b, 0) : null;
  }));
  return { observed_usage: usage, frame_timing_by_phase: frameTiming,
    max_frame_msec: samples.length ? Math.max(...samples.map(s => s.godot.max_frame_msec)) : null,
    total_frames_over_50_msec: samples.at(-1)?.godot.frames_over_50_msec ?? null };
}

async function bounded(promise, milliseconds, label) {
  let timer;
  try { return await Promise.race([promise, new Promise((_, reject) => { timer = setTimeout(() => reject(new Error(`Timed out: ${label}`)), milliseconds); })]); }
  finally { clearTimeout(timer); }
}

function installTelemetry() {
  // WeakRef를 써서 계측 코드가 해제 가능한 엔진 메모리의 수명을 연장하지 않는다.
  const memories = [], seen = new WeakSet(), events = [];
  const activeSources = new Map();
  const audio = { created: 0, started: 0, ended: 0, stop_calls: 0, disconnect_calls: 0, collected_without_ended: 0, supported: false };
  const audioPrototype = globalThis.BaseAudioContext?.prototype;
  if (typeof audioPrototype?.createBufferSource === 'function') {
    audio.supported = true;
    const originalCreate = audioPrototype.createBufferSource;
    audioPrototype.createBufferSource = function (...args) {
      const node = originalCreate.apply(this, args), id = ++audio.created;
      const record = { reference: new WeakRef(node), duration: 0, loop: false, disconnected: false, started_at_ms: 0 };
      const originalStart = node.start, originalStop = node.stop, originalDisconnect = node.disconnect;
      node.start = function (...startArgs) {
        const result = originalStart.apply(this, startArgs);
        audio.started++; record.duration = this.buffer?.duration || 0; record.loop = this.loop;
        record.started_at_ms = performance.now(); activeSources.set(id, record);
        return result;
      };
      node.stop = function (...stopArgs) { const result = originalStop.apply(this, stopArgs); audio.stop_calls++; return result; };
      node.disconnect = function (...disconnectArgs) {
        const result = originalDisconnect.apply(this, disconnectArgs);
        audio.disconnect_calls++; record.disconnected = true; return result;
      };
      node.addEventListener('ended', () => { audio.ended++; activeSources.delete(id); }, { once: true });
      return node;
    };
  }
  const remember = result => {
    const instance = result instanceof WebAssembly.Instance ? result : result?.instance;
    if (instance) for (const value of Object.values(instance.exports)) {
      if (value instanceof WebAssembly.Memory && !seen.has(value)) { seen.add(value); memories.push(new WeakRef(value)); }
    }
    return result;
  };
  for (const key of ['instantiate', 'instantiateStreaming']) {
    const original = WebAssembly[key];
    if (typeof original === 'function') WebAssembly[key] = function (...args) { return original.apply(this, args).then(remember); };
  }
  document.addEventListener('webglcontextlost', event => events.push({ type: 'webglcontextlost', at_ms: performance.now(), status: event.statusMessage || '' }), true);
  document.addEventListener('webglcontextrestored', () => events.push({ type: 'webglcontextrestored', at_ms: performance.now() }), true);
  window.__projectRdMemoryRead = () => {
    const capacities = memories.map(ref => ref.deref()?.buffer.byteLength).filter(Number.isFinite);
    const heap = performance.memory;
    let active = 0, activeLong = 0, disconnectedActive = 0, oldestLongMs = 0;
    for (const [id, record] of activeSources) {
      if (!record.reference.deref()) { activeSources.delete(id); audio.collected_without_ended++; continue; }
      active++;
      if (record.disconnected) disconnectedActive++;
      if (record.duration > 10) { activeLong++; oldestLongMs = Math.max(oldestLongMs, performance.now() - record.started_at_ms); }
    }
    return { wasm_capacity_bytes: capacities.length ? capacities.reduce((a, b) => a + b, 0) : null,
      wasm_memories: capacities.length, js_heap_used_bytes: heap?.usedJSHeapSize ?? null,
      js_heap_total_bytes: heap?.totalJSHeapSize ?? null, js_heap_limit_bytes: heap?.jsHeapSizeLimit ?? null,
      context_events: events.slice(), web_audio: { ...audio, active_buffer_sources: active, active_long_buffer_sources: activeLong, disconnected_active_sources: disconnectedActive, oldest_long_source_age_ms: oldestLongMs } };
  };
}

function linuxMemory(pid) {
  try {
    const status = fs.readFileSync(`/proc/${pid}/status`, 'utf8');
    const field = name => { const found = status.match(new RegExp(`^${name}:\\s+(\\d+) kB`, 'm')); return found ? Number(found[1]) * 1024 : null; };
    return { rss_bytes: field('VmRSS'), peak_rss_bytes: field('VmHWM'), virtual_bytes: field('VmSize') };
  } catch { return { rss_bytes: null, peak_rss_bytes: null, virtual_bytes: null }; }
}

async function main(options) {
  const outDir = path.resolve(options.output);
  fs.mkdirSync(outDir, { recursive: true });
  const paths = Object.fromEntries(['samples', 'events'].map(name => [name, path.join(outDir, `${name}.jsonl`)]));
  Object.values(paths).forEach(file => fs.writeFileSync(file, ''));
  const startedAt = new Date().toISOString(), startedMs = Date.now(), failures = [], checkpoints = [], samples = [], screenshots = [];
  let browser, page, context, pageCdp, browserCdp, sampleTimer, sampleInFlight = false, stopping = false, fatalError = null;
  let phase = 'boot', cycle = 0, lastState = null, lastHeartbeat = Date.now(), lastFrame = null, lastSample = null, maxWave = 0, completedBattles = 0;
  let sampleQueue = Promise.resolve(), overlappingMusicSamples = 0;
  let normalClosing = false, debugBuild = null, version = null, browserArguments = ['--no-sandbox', '--enable-webgl', '--ignore-gpu-blocklist', '--use-gl=angle', '--use-angle=swiftshader', '--enable-precise-memory-info'];
  const event = (type, detail) => { const item = { elapsed_ms: Date.now() - startedMs, phase, cycle, type, detail }; fs.appendFileSync(paths.events, JSON.stringify(item) + '\n'); };
  const fail = message => { failures.push(message); event('failure', message); };
  const guard = () => { if (fatalError) throw fatalError; if (Date.now() - startedMs > options.runTimeout) throw new Error('Overall soak run timeout'); };
  async function state() {
    guard();
    const result = await bounded(page.evaluate(() => { const s = window.__projectRdQa; return typeof s === 'function' ? s() : s; }), options.timeout, 'read QA bridge');
    if (result) { lastState = result; maxWave = Math.max(maxWave, result.wave || 0); }
    return result;
  }
  async function waitFor(predicate, label, timeout = options.timeout) {
    const until = Date.now() + timeout;
    do { guard(); const s = await state(); if (s && predicate(s)) return s; await page.waitForTimeout(150); } while (Date.now() < until);
    throw new Error(`Waiting for ${label}; mode=${lastState?.mode}, panel=${lastState?.panel_name}, wave=${lastState?.wave}`);
  }
  async function clickButton(name) {
    const s = await state(), button = s?.buttons?.[name];
    if (!button || button.disabled) throw new Error(`Visible enabled action missing: ${name}`);
    await clickLogical(button.x + button.width / 2, button.y + button.height / 2, s);
  }
  async function clickLogical(x, y, s = null) {
    s ||= await state();
    const rect = await page.locator('canvas').first().boundingBox();
    if (!rect) throw new Error('Canvas is not visible');
    const [width, height] = s.frame_size, scale = Math.min(rect.width / width, rect.height / height);
    await page.mouse.click(rect.x + (rect.width - width * scale) / 2 + x * scale,
      rect.y + (rect.height - height * scale) / 2 + y * scale);
  }
  function sample(label = phase) {
    const next = sampleQueue.then(() => readSample(label));
    sampleQueue = next.catch(() => {});
    return next;
  }
  async function readSample(label) {
    const observed = await bounded(page.evaluate(() => ({ godot: window.__projectRdQa, browser: window.__projectRdMemoryRead?.() })), options.timeout, 'memory sample');
    if (!observed.godot?.memory) throw new Error('Missing QA memory instrumentation; re-export current main.gd');
    const s = observed.godot, now = Date.now();
    lastState = s; maxWave = Math.max(maxWave, s.wave || 0);
    if (s.qa_process_frames !== lastFrame) { lastFrame = s.qa_process_frames; lastHeartbeat = now; }
    else if (now - lastHeartbeat > options.stallMs) throw new Error(`Godot frame heartbeat stalled for ${now - lastHeartbeat}ms`);
    const [performanceMetrics, dom, processes] = await Promise.all([
      pageCdp.send('Performance.getMetrics'), pageCdp.send('Memory.getDOMCounters'), browserCdp.send('SystemInfo.getProcessInfo')]);
    const current = { elapsed_ms: now - startedMs, label, phase, cycle,
      godot: { mode: s.mode, panel_name: s.panel_name, wave: s.wave, time: s.time, result: s.result, gold: s.gold, lives: s.lives,
        unit_count: s.units.length, enemy_count: s.enemy_count, pause_reasons: s.pause_reasons, process_frames: s.qa_process_frames,
        max_frame_msec: s.qa_max_frame_msec, frames_over_50_msec: s.qa_frames_over_50_msec, memory: s.memory, memory_caches: s.memory_caches || null },
      browser: { ...observed.browser, cdp_metrics: Object.fromEntries(performanceMetrics.metrics.map(metric => [metric.name, metric.value])), dom,
        processes: processes.processInfo.map(process => ({ pid: process.id, type: process.type, cpu_seconds: process.cpuTime, ...linuxMemory(process.id) })) } };
    if (lastSample) {
      const elapsed = current.elapsed_ms - lastSample.elapsed_ms;
      current.frame_interval = { elapsed_ms: elapsed, fps: elapsed ? (s.qa_process_frames - lastSample.godot.process_frames) * 1000 / elapsed : null,
        frames_over_50_msec: s.qa_frames_over_50_msec - lastSample.godot.frames_over_50_msec };
    }
    lastSample = current;
    samples.push(current); fs.appendFileSync(paths.samples, JSON.stringify(current) + '\n');
    const audio = current.browser.web_audio;
    overlappingMusicSamples = audio?.active_long_buffer_sources > 3 && audio.oldest_long_source_age_ms > 5000 ? overlappingMusicSamples + 1 : 0;
    if (overlappingMusicSamples >= 3) {
      throw new Error(`Sustained overlapping music sources: ${audio.active_long_buffer_sources} long buffers, ${audio.disconnected_active_sources} disconnected-active; stopping before browser OOM`);
    }
    if (observed.browser?.context_events.some(item => item.type === 'webglcontextlost')) throw new Error('WebGL context lost');
    return current;
  }
  async function capture(name) { const file = path.join(outDir, `${name}.png`); await page.screenshot({ path: file, timeout: options.timeout }); screenshots.push(file); }
  async function pause() {
    const s = await state();
    if (s.result === 'active' && !Object.keys(s.pause_reasons).length) { await clickButton('pause'); await waitFor(v => Object.keys(v.pause_reasons).length > 0, 'pause'); }
  }
  async function codex() {
    phase = 'codex'; await clickButton('codex'); await waitFor(s => s.panel_name === 'codex', 'codex open');
    for (const tab of ['enemies', 'units']) {
      await clickButton(`codex_${tab}`); await waitFor(s => s.codex_tab === tab, `codex ${tab}`);
      if (tab === 'enemies') for (const filter of ['normal', 'boss', 'special', 'all']) {
        await clickButton(`codex_filter_${filter}`); await waitFor(s => s.enemy_filter === filter, `codex filter ${filter}`);
      }
      // 실제 스크롤 이벤트로 목록 끝과 시작을 반복하여 표시 리소스 경로를 거친다.
      const rect = await page.locator('canvas').first().boundingBox();
      await page.mouse.move(rect.x + rect.width / 2, rect.y + rect.height * 0.62);
      await page.mouse.wheel(0, 6000); await page.waitForTimeout(200); await page.mouse.wheel(0, -6000);
    }
    await sample('codex-open');
    await clickButton('close_panel'); await waitFor(s => s.panel_name === '', 'codex close');
  }
  async function menu() {
    const s = await state();
    if (s.mode === 'battle') {
      if (s.result !== 'active') { await waitFor(v => v.buttons?.result_menu, 'result menu button'); await clickButton('result_menu'); }
      else { await clickButton('settings'); await waitFor(v => v.panel_name === 'settings', 'settings'); await clickButton('save_menu'); }
    }
    await waitFor(v => v.mode === 'menu' && !v.panel_name, 'main menu');
    if (lastState.save_error) throw new Error(`Save error: ${lastState.save_error}`);
  }
  async function newBattle() {
    await clickButton('new_game');
    const s = await waitFor(v => v.mode === 'battle' || v.buttons?.confirm_new, 'new game or confirmation');
    if (s.buttons?.confirm_new) await clickButton('confirm_new');
    await waitFor(v => v.mode === 'battle' && !v.panel_name && v.units.length === 0, 'empty new battle');
    for (let i = 1; i <= 3; i++) { await clickButton('summon'); await waitFor(v => v.units.length === i, `summon ${i}`); }
    for (const speed of [2, 3, 5]) { await clickButton('speed'); await waitFor(v => v.speed === speed, `speed ${speed}`); }
  }
  async function fight(seconds) {
    const s = await state(), startTime = s.time, until = Date.now() + seconds * 1000;
    while (Date.now() < until) {
      guard(); await page.waitForTimeout(Math.min(1000, Math.max(1, until - Date.now())));
      const current = await state();
      if (current.result !== 'active') { completedBattles++; event('battle-result', { result: current.result, wave: current.wave, game_seconds: current.time }); return; }
      if (Object.keys(current.pause_reasons).length) throw new Error(`Unexpected pause during soak: ${JSON.stringify(current.pause_reasons)}`);
    }
    if ((await state()).time <= startTime + 0.1) throw new Error('Battle simulation did not advance during continuous play');
  }
  let error = null;
  try {
    browser = await chromium.launch({ headless: true, executablePath: process.env.CHROMIUM_PATH || (fs.existsSync('/usr/bin/chromium') ? '/usr/bin/chromium' : undefined), args: browserArguments });
    version = browser.version();
    browser.on('disconnected', () => { if (!normalClosing) { fatalError = new Error('Browser disconnected unexpectedly'); fail(fatalError.message); } });
    context = await browser.newContext({ viewport: { width: 720, height: 1280 }, deviceScaleFactor: 1 });
    await context.addInitScript(installTelemetry);
    page = await context.newPage(); page.setDefaultTimeout(options.timeout);
    page.on('crash', () => { fatalError = new Error('Browser renderer page crashed'); fail(fatalError.message); });
    page.on('pageerror', cause => fail(`pageerror: ${cause.message}`));
    page.on('console', message => { event(`console-${message.type()}`, message.text()); if (message.type() === 'error' || /SCRIPT ERROR:|(^|\s)ERROR:|Out of memory|memory access out of bounds|Aborted\(/i.test(message.text())) fail(message.text()); });
    page.on('requestfailed', request => { event('requestfailed', { url: request.url(), error: request.failure()?.errorText }); fail(`requestfailed: ${request.url()}: ${request.failure()?.errorText}`); });
    page.on('response', response => { if (response.status() >= 400) fail(`HTTP ${response.status()}: ${response.url()}`); });
    pageCdp = await context.newCDPSession(page); browserCdp = await browser.newBrowserCDPSession(); await pageCdp.send('Performance.enable');
    const url = new URL(options.baseUrl); url.searchParams.set('qa', '1');
    await page.goto(url.href, { waitUntil: 'domcontentloaded', timeout: options.bootTimeout });
    const initial = await waitFor(s => s.mode === 'menu' && s.memory && s.qa_process_frames > 0, 'instrumented menu', options.bootTimeout);
    if (!initial.art_ready) throw new Error('Initial art readiness flag is false');
    debugBuild = initial.qa_debug_build;
    if (!debugBuild && !options.allowRelease) throw new Error('Debug Web export required for full live-memory evidence; use WEB_EXPORT_MODE=debug, or --allow-release for explicitly partial telemetry');
    if (!(initial.memory.node_count > 0 && initial.memory.resource_count > 0)) throw new Error('Required live node/resource monitors are unavailable');
    await sample('boot-menu'); await capture('boot-menu');
    if (options.musicOff) {
      phase = 'mute-music-control';
      const originalEffects = initial.save_profile.settings.effects;
      await clickButton('settings'); await waitFor(s => s.panel_name === 'settings', 'music settings');
      // 기존 HSlider의 왼쪽 끝을 실제 클릭한다. 저장 프로필 관측값으로 적용을 확인한다.
      await clickLogical(251, 388);
      await waitFor(s => s.save_profile?.settings?.music === 0, 'music volume zero');
      if (lastState.save_profile.settings.effects !== originalEffects) throw new Error('Music-only control changed effects volume');
      await clickButton('close_panel'); await waitFor(s => !s.panel_name, 'close music settings');
      event('music-muted-control', { music: lastState.save_profile.settings.music, effects: originalEffects });
    }
    sampleTimer = setInterval(async () => {
      if (sampleInFlight || stopping || fatalError) return;
      sampleInFlight = true;
      try { await sample(); } catch (cause) { fatalError = cause; fail(`sample: ${cause.message}`); }
      finally { sampleInFlight = false; }
    }, options.sampleIntervalMs);
    for (cycle = 1; cycle <= options.cycles; cycle++) {
      guard(); phase = 'new-battle'; await newBattle();
      phase = 'continuous-battle'; await fight(options.battleSeconds);
      if (lastState.result === 'active') {
        await pause(); await codex();
        for (const panel of ['guide', 'recipes']) { await clickButton(panel); await waitFor(s => s.panel_name === panel, panel); await clickButton('close_panel'); await waitFor(s => !s.panel_name, `${panel} close`); }
        await menu();
        phase = 'continue'; await clickButton('continue'); await waitFor(s => s.mode === 'battle' && Object.keys(s.pause_reasons).length, 'paused saved battle');
      }
      phase = 'return-menu'; await menu(); await codex(); phase = 'settled-menu';
      await page.waitForTimeout(options.settleMs);
      const checkpoint = await sample('settled-menu'); checkpoints.push(checkpoint);
      event('cycle-complete', { cycle, memory: checkpoint.godot.memory, wasm_capacity_bytes: checkpoint.browser.wasm_capacity_bytes });
      process.stdout.write(`cycle ${cycle}/${options.cycles} menu resources=${checkpoint.godot.memory.resource_count} objects=${checkpoint.godot.memory.object_count} textureMiB=${(checkpoint.godot.memory.texture_bytes / MiB).toFixed(2)} staticMiB=${(checkpoint.godot.memory.static_bytes / MiB).toFixed(2)} wasmMiB=${(checkpoint.browser.wasm_capacity_bytes / MiB).toFixed(2)}\n`);
    }
    if (options.enduranceSeconds > 0) {
      cycle = options.cycles; phase = 'endurance-new'; await newBattle(); phase = 'endurance-battle'; await capture('endurance-start');
      // 실제 종료가 나오면 정상 종료 경로를 확인하고 남은 실제 시간 동안 새 전투를 이어간다.
      const until = Date.now() + options.enduranceSeconds * 1000;
      while (Date.now() < until) { await fight(Math.max(1, (until - Date.now()) / 1000)); if (Date.now() < until && lastState.result !== 'active') { await menu(); await newBattle(); phase = 'endurance-battle'; } }
      await capture('endurance-finish'); phase = 'final-menu'; await menu(); await page.waitForTimeout(options.settleMs); await sample('final-menu');
    }
    phase = 'complete'; await capture('final-menu'); guard();
  } catch (cause) {
    error = cause.stack || String(cause); fail(error);
    if (page && !page.isClosed()) await capture('failure').catch(() => {});
  } finally {
    stopping = true; clearInterval(sampleTimer);
    // 마지막 비동기 샘플을 기다려 로그 기록 후 브라우저를 닫는다.
    const deadline = Date.now() + options.timeout;
    while (sampleInFlight && Date.now() < deadline) await new Promise(resolve => setTimeout(resolve, 50));
    normalClosing = true;
    if (browser) await bounded(browser.close(), options.timeout, 'close browser').catch(cause => fail(cause.message));
  }
  const analysis = analyze(checkpoints, options.warmupCycles, debugBuild);
  if (analysis.regressions.length) fail(`Settled lifecycle growth: ${analysis.regressions.join(', ')}`);
  // 전체 핸들러는 GC에 맡기되, 음악 플레이어 하나가 긴 음원을 겹쳐 재생하면 실패다.
  const overlappingMusic = samples.filter(s => s.browser.web_audio?.active_long_buffer_sources > 3 && s.browser.web_audio.oldest_long_source_age_ms > 5000);
  if (overlappingMusic.length >= 3) fail(`Concurrent long WebAudio sources exceeded one music player's bounded lifetime in ${overlappingMusic.length} samples`);
  if (checkpoints.length !== options.cycles) fail(`Completed ${checkpoints.length}/${options.cycles} cycles`);
  if (!samples.some(s => s.browser.wasm_capacity_bytes > 0)) fail('Wasm capacity telemetry was not observed');
  let revision = null;
  try { revision = execFileSync('git', ['rev-parse', 'HEAD'], { encoding: 'utf8' }).trim(); } catch { /* 저장소 밖에서도 실행 가능하다. */ }
  const report = { result: failures.length ? 'fail' : 'pass', started_at: startedAt, finished_at: new Date().toISOString(), duration_ms: Date.now() - startedMs,
    options, source_revision: revision, browser_version: version, browser_arguments: browserArguments, playwright_version: require('playwright/package.json').version,
    debug_build: debugBuild, cycles_completed: checkpoints.length, completed_battles: completedBattles, max_wave: maxWave, sample_count: samples.length,
    analysis, observations: summarizeSamples(samples), checkpoints, failures, error, last_state: lastState, screenshots, logs: paths };
  fs.writeFileSync(path.join(outDir, 'report.json'), JSON.stringify(report, null, 2) + '\n');
  process.stdout.write(JSON.stringify({ result: report.result, duration_ms: report.duration_ms, cycles_completed: report.cycles_completed, max_wave: maxWave, analysis, failures, report: path.join(outDir, 'report.json') }, null, 2) + '\n');
  if (failures.length) process.exitCode = 1;
}

function selfTest() {
  assert.equal(trend([10, 10, 10]).slope_per_cycle, 0);
  assert.deepEqual([trend([1, 3, 5]).delta, trend([1, 3, 5]).slope_per_cycle], [4, 2]);
  assert.equal(trend([null, null]).supported, false);
  const fixtures = [1, 2, 3, 4].map(cycle => ({ cycle, godot: { memory: { static_bytes: 20 * MiB, object_count: 300, node_count: 25, orphan_node_count: 0, resource_count: 100, texture_bytes: 12 * MiB, buffer_bytes: MiB, video_bytes: 13 * MiB } }, browser: { wasm_capacity_bytes: (128 + cycle * 32) * MiB, js_heap_used_bytes: 5 * MiB } }));
  assert.deepEqual(analyze(fixtures, 1, true).regressions, []);
  fixtures[3].godot.memory.orphan_node_count = 1;
  assert.deepEqual(analyze(fixtures, 1, true).regressions, ['orphan_node_count']);
  assert.equal(analyze(fixtures, 1, false).settled_menu_metrics.static_bytes.supported, false);
  fixtures.forEach((item, index) => { item.godot.memory.orphan_node_count = 0; item.browser.cdp_metrics = { AudioHandlers: index * 50 }; item.browser.dom = { nodes: 5, jsEventListeners: 3 }; });
  assert.deepEqual(analyze(fixtures, 1, true).regressions, []);
  assert.equal(analyze(fixtures, 1, true).browser_lifecycle.audio_handlers.diagnostic_only, true);
  assert.throws(() => parseArgs(['node', 'soak', '--cycles', '4', '--warmup-cycles', '3']));
  assert.throws(() => parseArgs(['node', 'soak', '--battle-seconds', 'NaN']));
  // 오디오 관측 래퍼는 인수·반환값·원래 종료 이벤트를 그대로 보존해야 한다.
  const originals = Object.fromEntries(['window', 'document', 'BaseAudioContext'].map(key => [key, Object.getOwnPropertyDescriptor(globalThis, key)]));
  const instantiate = WebAssembly.instantiate, streaming = WebAssembly.instantiateStreaming;
  class FakeAudioContext {
    createBufferSource() {
      return { buffer: { duration: 60 }, loop: true, events: {},
        start(...args) { this.startArgs = args; return 'started'; }, stop() { return 'stopped'; }, disconnect() { return 'disconnected'; },
        addEventListener(type, callback) { this.events[type] = callback; } };
    }
  }
  try {
    globalThis.window = {};
    globalThis.document = { addEventListener() {} };
    globalThis.BaseAudioContext = FakeAudioContext;
    installTelemetry();
    const node = new FakeAudioContext().createBufferSource();
    assert.equal(node.start(2, 3), 'started'); assert.deepEqual(node.startArgs, [2, 3]);
    assert.equal(node.disconnect(), 'disconnected');
    let audio = window.__projectRdMemoryRead().web_audio;
    assert.equal(audio.active_long_buffer_sources, 1); assert.equal(audio.disconnected_active_sources, 1);
    assert.equal(node.stop(), 'stopped'); node.events.ended();
    audio = window.__projectRdMemoryRead().web_audio;
    assert.equal(audio.active_buffer_sources, 0); assert.equal(audio.ended, 1); assert.equal(audio.stop_calls, 1);
  } finally {
    WebAssembly.instantiate = instantiate; WebAssembly.instantiateStreaming = streaming;
    for (const [key, descriptor] of Object.entries(originals)) { if (descriptor) Object.defineProperty(globalThis, key, descriptor); else delete globalThis[key]; }
  }
  process.stdout.write('MEMORY_SOAK_SELF_TEST_PASS\n');
}

module.exports = { analyze, summarizeSamples };
if (require.main === module) {
  const options = parseArgs(process.argv);
  if (options.selfTest) selfTest();
  else main(options).catch(error => { process.stderr.write(`${error.stack || error}\n`); process.exitCode = 1; });
}
