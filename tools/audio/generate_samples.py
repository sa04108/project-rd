#!/usr/bin/env python3
"""외부 녹음 없이 재현 가능한 게임 오디오 샘플을 생성합니다."""

from __future__ import annotations

import hashlib
import json
import math
import shutil
import subprocess
import tempfile
import wave
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "assets/audio"
MUSIC_RATE = 32_000
SFX_RATE = 22_050


def note_freq(note: int) -> float:
    return 440.0 * (2.0 ** ((note - 69) / 12.0))


def tone(freq: float, t: np.ndarray, harmonics: tuple[float, ...]) -> np.ndarray:
    return sum(weight * np.sin(2 * np.pi * freq * harmonic * t) for harmonic, weight in enumerate(harmonics, 1))


def add_note(buf: np.ndarray, start: float, length: float, midi: int, level: float,
             harmonics: tuple[float, ...], rate: int, pan: float = 0.0,
             attack: float = 0.12, release: float = 0.35, vibrato: float = 0.0) -> None:
    """부드러운 어택과 릴리스가 있는 음을 스테레오 버퍼에 더합니다."""
    begin = max(0, int(start * rate))
    end = min(len(buf), int((start + length) * rate))
    if end <= begin:
        return
    t = np.arange(end - begin, dtype=np.float64) / rate
    f = note_freq(midi)
    phase = 2 * np.pi * f * t + vibrato * np.sin(2 * np.pi * 4.3 * t)
    sound = sum(weight * np.sin(phase * harmonic) for harmonic, weight in enumerate(harmonics, 1))
    env = np.minimum(1.0, t / max(attack, 0.001))
    env *= np.minimum(1.0, np.maximum(0, length - t) / max(release, 0.001))
    # 낮은 음량의 미세한 진폭 변조로 정적인 신스를 피합니다.
    env *= 0.92 + 0.08 * np.sin(2 * np.pi * 0.19 * t + start)
    left = math.sqrt((1 - pan) / 2)
    right = math.sqrt((1 + pan) / 2)
    buf[begin:end, 0] += level * sound * env * left
    buf[begin:end, 1] += level * sound * env * right


def make_music(style: str) -> np.ndarray:
    """서로 다른 질감과 코드 진행을 가진 32초 루프를 만듭니다."""
    # 교차 구간을 포함해 합성하고, 마지막에 그 구간을 겹쳐 정확히 32초로 만듭니다.
    duration = 32.48
    buf = np.zeros((int(duration * MUSIC_RATE), 2), dtype=np.float64)
    t = np.arange(len(buf), dtype=np.float64) / MUSIC_RATE
    if style == "hearth_watch":
        chords = [(48, 55, 60, 64), (45, 52, 57, 60), (41, 48, 53, 57), (43, 50, 55, 59)]
        pad = (1.0, 0.24, 0.07, 0.025)
        lead = (1.0, 0.50, 0.17, 0.04)
        melody = [72, 76, 79, 76, 74, 72, 67, 69, 72, 76, 74, 71, 67, 71, 74, 72]
        accompaniment = (0.9, 0.28, 0.10, 0.02)
        drone = 0.22
    elif style == "mist_guard":
        chords = [(50, 57, 62, 66), (46, 53, 58, 62), (48, 55, 60, 65), (45, 52, 57, 62)]
        pad = (1.0, 0.08, 0.025)
        lead = (1.0, 0.16, 0.035)
        melody = [78, 81, 86, 83, 79, 84, 88, 84, 81, 78, 74, 79, 83, 86, 83, 79]
        accompaniment = (1.0, 0.12, 0.03)
        drone = 0.12
    else:
        chords = [(43, 50, 55, 59), (41, 48, 53, 57), (38, 45, 50, 55), (40, 47, 52, 55)]
        pad = (1.0, 0.16, 0.04)
        lead = (1.0, 0.34, 0.09)
        melody = [67, 71, 74, 71, 69, 72, 76, 72, 67, 74, 79, 74, 71, 76, 79, 76]
        accompaniment = (1.0, 0.2, 0.06)
        drone = 0.28

    # 네 개 코드가 각각 두 마디(8초) 동안 이어집니다.
    for bar, chord in enumerate(chords):
        start = bar * 8.0
        for index, midi in enumerate(chord):
            add_note(buf, start, 8.0, midi, (0.040 if index else 0.065), pad,
                     MUSIC_RATE, pan=(-0.25 if index % 2 else 0.25), attack=1.6, release=1.7)
        # 두 박마다 낮은 플럭을 두어 코드 진행을 또렷하게 들려줍니다.
        for beat in range(4):
            add_note(buf, start + beat * 2.0, 1.7, chord[0] + 12, 0.028,
                     accompaniment, MUSIC_RATE, pan=(-0.18 if beat % 2 else 0.18),
                     attack=0.14, release=0.7)
            add_note(buf, start + beat * 2.0 + 0.95, 1.05, chord[2] + 12, 0.012,
                     accompaniment, MUSIC_RATE, pan=0.15, attack=0.12, release=0.55)

    # 긴 저음과 느린 고역의 움직임으로 각 테마의 공간감을 만듭니다.
    if style == "mist_guard":
        for midi, gain, speed, phase in [(38, drone, 0.11, 0.1), (57, 0.028, 0.23, 1.7)]:
            buf[:, 0] += gain * np.sin(2 * np.pi * note_freq(midi) * t + phase)
            buf[:, 1] += gain * np.sin(2 * np.pi * note_freq(midi) * 1.005 * t + phase + 0.4)
        for onset, midi in zip([1, 5, 9, 13, 17, 21, 25, 29], [86, 81, 88, 83, 86, 79, 84, 81]):
            add_note(buf, onset, 2.6, midi, 0.012, (1.0, 0.09, 0.02), MUSIC_RATE,
                     pan=0.4 if onset % 2 else -0.4, attack=0.6, release=1.0, vibrato=0.045)
    elif style == "quiet_march":
        # 둥근 현악 저음이 80 BPM의 맥박을 만들되 타악기처럼 튀지 않습니다.
        for beat in range(32):
            chord = chords[(beat // 8)]
            add_note(buf, beat, 0.82, chord[0], 0.052, (1.0, 0.10, 0.02), MUSIC_RATE,
                     pan=(-0.1 if beat % 2 else 0.1), attack=0.08, release=0.43)
            if beat % 2 == 1:
                add_note(buf, beat + 0.02, 0.6, chord[2], 0.025, (1.0, 0.16, 0.03),
                         MUSIC_RATE, pan=0.15, attack=0.08, release=0.36)
    else:
        for midi, gain, phase in [(36, drone, 0.0), (55, 0.025, 0.8)]:
            wave = np.sin(2 * np.pi * note_freq(midi) * t + phase)
            buf[:, 0] += gain * wave
            buf[:, 1] += gain * np.sin(2 * np.pi * note_freq(midi) * 1.002 * t + phase)

    # 서로 다른 멜로디 리듬으로 세 트랙을 구분하고, 마지막 음은 루프 경계 전에 놓습니다.
    if style == "hearth_watch":
        onsets = [0.5 + i * 2 for i in range(16)]
        lengths = [1.05] * 16
    elif style == "mist_guard":
        onsets = [0.75 + i * 2 for i in range(16)]
        lengths = [1.1] * 16
    else:
        onsets = [0.35 + i * 2 for i in range(16)]
        lengths = [0.88] * 16
    for i, (onset, midi, length) in enumerate(zip(onsets, melody, lengths)):
        add_note(buf, onset, length, midi, 0.022 if style == "mist_guard" else 0.030,
                 lead, MUSIC_RATE, pan=(-0.28 if i % 2 else 0.28), attack=0.12,
                 release=0.42, vibrato=0.018 if style == "hearth_watch" else 0.04)

    # 마지막 0.48초와 첫 0.48초를 smoothstep으로 겹쳐 자연스러운 반복 경계를 만듭니다.
    edge = int(0.48 * MUSIC_RATE)
    fade = np.linspace(0.0, 1.0, edge, endpoint=True)
    fade = fade * fade * (3.0 - 2.0 * fade)
    overlap = buf[-edge:] * (1.0 - fade[:, None]) + buf[:edge] * fade[:, None]
    buf = np.concatenate((overlap, buf[edge:-edge]), axis=0)
    # 양끝의 샘플 값과 기울기가 모두 낮은 지점으로 루프 시작점을 옮깁니다.
    energy = np.sum(buf ** 2, axis=1)
    candidates = energy + np.roll(energy, 1)
    start_at = int(np.argmin(candidates))
    buf = np.roll(buf, -start_at, axis=0)
    # 짧은 10ms 페이드와 30ms 무음 가드로 코덱 경계의 클릭을 줄입니다.
    cap = int(0.010 * MUSIC_RATE)
    edge_fade = np.linspace(0.0, 1.0, cap, endpoint=True)
    edge_fade = edge_fade * edge_fade * (3.0 - 2.0 * edge_fade)
    buf[:cap] *= edge_fade[:, None]
    buf[-cap:] *= edge_fade[::-1, None]
    guard = int(0.030 * MUSIC_RATE)
    buf[:guard] = 0.0
    buf[-guard:] = 0.0
    # 양 채널별 평균 성분을 제거해 인코딩 뒤에도 DC 오프셋을 억제합니다.
    buf -= np.mean(buf, axis=0, keepdims=True)
    # 완만한 소프트 리미터와 목표 RMS로 테마 간 체감 음량을 가깝게 맞춥니다.
    low, high = 0.0, 16.0
    for _ in range(32):
        gain = (low + high) * 0.5
        candidate = 0.15 * np.tanh(buf * (16.0 * gain) / 0.15)
        if float(np.sqrt(np.mean(candidate ** 2))) < 0.050:
            low = gain
        else:
            high = gain
    return 0.15 * np.tanh(buf * (16.0 * high) / 0.15)


def envelope(n: int, rate: int, attack: float, release: float) -> np.ndarray:
    t = np.arange(n) / rate
    env = np.minimum(1.0, t / max(attack, 1e-4))
    env *= np.minimum(1.0, np.maximum(0, n / rate - t) / max(release, 1e-4))
    return env


def make_sfx(kind: str) -> np.ndarray:
    """무기별 차이를 살린 짧고 낮은 음량의 효과음을 만듭니다."""
    durations = {"wood": 0.17, "tap": 0.085, "chime": 0.21,
                 "blade": 0.38, "bow": 0.31, "blunt": 0.40, "magic": 0.48, "shot": 0.34}
    rate = SFX_RATE
    n = int(durations[kind] * rate)
    t = np.arange(n, dtype=np.float64) / rate
    rng = np.random.default_rng(sum(ord(c) for c in kind))
    noise = rng.normal(0, 1, n)

    if kind == "wood":
        env = envelope(n, rate, 0.003, 0.10)
        mono = 0.18 * env * (0.72 * np.sin(2*np.pi*690*t) + 0.28*np.sin(2*np.pi*1120*t))
        mono += 0.035 * noise * env
    elif kind == "tap":
        env = np.exp(-t * 54)
        mono = 0.15 * env * (np.sin(2*np.pi*920*t) + 0.28*np.sin(2*np.pi*1450*t))
    elif kind == "chime":
        env = envelope(n, rate, 0.006, 0.19)
        mono = 0.13 * env * (np.sin(2*np.pi*1046*t) + 0.36*np.sin(2*np.pi*1568*t) + 0.12*np.sin(2*np.pi*2093*t))
    elif kind == "blade":
        env = envelope(n, rate, 0.012, 0.17)
        sweep = 950 - 570 * t / durations[kind]
        mono = 0.115 * env * np.sin(2*np.pi*np.cumsum(sweep)/rate)
        mono += 0.027 * noise * env
    elif kind == "bow":
        env = envelope(n, rate, 0.014, 0.15)
        # 활시위의 낮은 당김음과 부드러운 화살 휘파람
        mono = 0.12 * env * np.sin(2*np.pi*125*t)
        mono += 0.025 * env * np.sin(2*np.pi*(530 + 180*t)*t)
        mono += 0.018 * noise * env
    elif kind == "blunt":
        env = np.exp(-t*14) * envelope(n, rate, 0.004, 0.23)
        f = 180 - 85 * t / durations[kind]
        mono = 0.16 * env * np.sin(2*np.pi*np.cumsum(f)/rate)
        mono += 0.023 * noise * env
    elif kind == "magic":
        env = envelope(n, rate, 0.045, 0.29)
        wobble = np.sin(2*np.pi*5.1*t)
        mono = 0.10 * env * (np.sin(2*np.pi*570*t + 0.14*wobble) + 0.42*np.sin(2*np.pi*855*t))
        mono += 0.018 * env * np.sin(2*np.pi*1140*t)
    else:  # 총기
        env = np.exp(-t*20) * envelope(n, rate, 0.002, 0.19)
        mono = 0.15 * env * (np.sin(2*np.pi*95*t) + 0.33*np.sin(2*np.pi*190*t))
        mono += 0.024 * noise * env

    # 마지막 8ms를 내리고 평균 성분을 제거해 팝과 DC를 방지합니다.
    tail = min(int(0.008 * rate), n)
    mono[-tail:] *= np.linspace(1, 0, tail)
    mono -= mono.mean()
    return mono


def write_wav(path: Path, samples: np.ndarray, rate: int) -> None:
    samples = np.asarray(samples)
    if samples.ndim == 1:
        samples = samples[:, None]
    pcm = np.round(np.clip(samples, -1, 1) * 32767).astype("<i2")
    with wave.open(str(path), "wb") as out:
        out.setnchannels(pcm.shape[1])
        out.setsampwidth(2)
        out.setframerate(rate)
        out.writeframes(pcm.tobytes())


def measure(path: Path, channels: int, rate: int) -> dict[str, float | int]:
    """생성된 PCM의 피크와 RMS를 선형값 및 dBFS로 기록합니다."""
    with wave.open(str(path), "rb") as src:
        frames = src.getnframes()
        raw = src.readframes(frames)
    pcm = np.frombuffer(raw, dtype="<i2").astype(np.float64) / 32768
    peak = float(np.max(np.abs(pcm)))
    rms = float(np.sqrt(np.mean(pcm**2)))
    metrics: dict[str, float | int] = {"sample_rate": rate, "channels": channels, "duration_seconds": round(frames / rate, 4),
            "peak": round(peak, 6), "peak_dbfs": round(20*math.log10(max(peak, 1e-12)), 2),
            "rms": round(rms, 6), "rms_dbfs": round(20*math.log10(max(rms, 1e-12)), 2),
            "bytes": path.stat().st_size, "sha256": hashlib.sha256(path.read_bytes()).hexdigest()}
    if channels > 1:
        frames_pcm = pcm.reshape(-1, channels)
        metrics["decoded_dc_max"] = round(float(np.max(np.abs(np.mean(frames_pcm, axis=0)))), 8)
        metrics["decoded_boundary_delta"] = round(float(np.max(np.abs(frames_pcm[0] - frames_pcm[-1]))), 6)
    return metrics


def main() -> None:
    if not shutil.which("ffmpeg"):
        raise SystemExit("ffmpeg가 필요합니다: libvorbis 인코더를 확인하세요.")
    manifest: dict[str, object] = {"generator": "tools/audio/generate_samples.py", "format_notes": "original deterministic procedural synthesis; no external recordings", "files": {}}
    files: dict[str, object] = manifest["files"]  # type: ignore[assignment]
    with tempfile.TemporaryDirectory(prefix="audio-samples-") as temp:
        tmp = Path(temp)
        for style in ("hearth_watch", "mist_guard", "quiet_march"):
            target = OUT / "music" / f"{style}.ogg"
            wav = tmp / f"{style}.wav"
            write_wav(wav, make_music(style), MUSIC_RATE)
            subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", str(wav), "-c:a", "libvorbis",
                            "-b:a", "56k", "-ar", str(MUSIC_RATE), "-ac", "2", str(target)], check=True)
            # Ogg를 같은 형식의 WAV로 디코드해 실제 재생 샘플의 레벨을 측정합니다.
            decoded = tmp / f"{style}-decoded.wav"
            subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", str(target), "-ar", str(MUSIC_RATE),
                            "-ac", "2", "-c:a", "pcm_s16le", str(decoded)], check=True)
            files[str(target.relative_to(ROOT))] = measure(decoded, 2, MUSIC_RATE) | {
                "bytes": target.stat().st_size, "decoded_pcm_bytes": decoded.stat().st_size,
                "encoded_bytes": target.stat().st_size,
                "sha256": hashlib.sha256(target.read_bytes()).hexdigest(), "format": "Ogg Vorbis 56 kbps"}
        for group, names in (("ui", ("wood", "tap", "chime")),
                             ("combat", ("blade", "bow", "blunt", "magic", "shot"))):
            for name in names:
                target = OUT / group / f"{name}.wav"
                write_wav(target, make_sfx(name), SFX_RATE)
                files[str(target.relative_to(ROOT))] = measure(target, 1, SFX_RATE) | {"format": "PCM16 mono"}
    manifest["total_bytes"] = sum((ROOT / p).stat().st_size for p in files)
    (OUT / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"Generated {len(files)} audio files ({manifest['total_bytes']:,} bytes)")


if __name__ == "__main__":
    main()
