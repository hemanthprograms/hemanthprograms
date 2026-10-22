#!/usr/bin/env python3
"""Generates SnoreGuard/Resources/SampleSnoring.m4a, the bundled test recording.

The clip is synthetic: 90 seconds of a quiet bedroom with two bouts of snore-like
breathing (a low palatal "flutter" pulse train shaped by throat resonances, plus
turbulent airflow noise). It exists so the file-based detector can be exercised in
the Simulator and in unit tests without anyone having to sleep next to a laptop.
Apple's classifier may or may not label it "snoring"; real recordings work better
and can be imported from the Start night screen.

Requires numpy and ffmpeg. Usage: python3 Tools/make_sample_audio.py
"""

import pathlib
import subprocess
import tempfile
import wave

import numpy as np

SAMPLE_RATE = 16_000
DURATION = 90.0
RNG = np.random.default_rng(7)
OUTPUT = pathlib.Path(__file__).resolve().parent.parent / "SnoreGuard" / "Resources" / "SampleSnoring.m4a"


def band_noise(count: int, low: float, high: float) -> np.ndarray:
    spectrum = np.fft.rfft(RNG.standard_normal(count))
    freqs = np.fft.rfftfreq(count, 1 / SAMPLE_RATE)
    spectrum[(freqs < low) | (freqs > high)] = 0
    signal = np.fft.irfft(spectrum, count)
    return signal / (np.max(np.abs(signal)) + 1e-9)


def snore(duration: float) -> np.ndarray:
    count = int(duration * SAMPLE_RATE)
    t = np.arange(count) / SAMPLE_RATE
    # Soft-palate flutter: a jittery pulse train around 30 Hz.
    f0 = 30 + 6 * np.sin(2 * np.pi * 0.6 * t) + RNG.normal(0, 2.0, count).cumsum() / count * 20
    phase = np.cumsum(f0) / SAMPLE_RATE
    pulses = np.zeros(count)
    onsets = np.where(np.diff(np.floor(phase)) > 0)[0]
    pulses[onsets] = 1 + 0.35 * RNG.standard_normal(len(onsets))
    # Throat and mouth resonances excited by each pulse.
    kt = np.arange(int(0.035 * SAMPLE_RATE)) / SAMPLE_RATE
    kernel = (
        1.0 * np.exp(-kt * 55) * np.sin(2 * np.pi * 95 * kt)
        + 0.8 * np.exp(-kt * 80) * np.sin(2 * np.pi * 210 * kt)
        + 0.5 * np.exp(-kt * 120) * np.sin(2 * np.pi * 480 * kt)
        + 0.25 * np.exp(-kt * 180) * np.sin(2 * np.pi * 950 * kt)
    )
    voiced = np.convolve(pulses, kernel)[:count]
    voiced /= np.max(np.abs(voiced)) + 1e-9
    # Rattling airflow, gated by the flutter.
    airflow = band_noise(count, 120, 2_400) * (0.45 + 0.55 * (0.5 + 0.5 * np.cos(2 * np.pi * phase)))
    envelope = np.sin(np.pi * t / duration) ** 0.5
    return (voiced + 0.4 * airflow) * envelope


def breath(duration: float, level: float) -> np.ndarray:
    count = int(duration * SAMPLE_RATE)
    t = np.arange(count) / SAMPLE_RATE
    return band_noise(count, 250, 1_800) * np.sin(np.pi * t / duration) ** 1.5 * level


def place(track: np.ndarray, clip: np.ndarray, at: float) -> None:
    start = int(at * SAMPLE_RATE)
    end = min(len(track), start + len(clip))
    track[start:end] += clip[: end - start]


def quiet_breathing(track: np.ndarray, start: float, end: float) -> None:
    cursor = start
    while cursor + 4.5 < end:
        place(track, breath(1.6, 0.025), cursor)
        place(track, breath(2.0, 0.018), cursor + 1.8)
        cursor += 4.6 + RNG.uniform(-0.3, 0.3)


def snoring_bout(track: np.ndarray, start: float, end: float) -> None:
    cursor = start
    while cursor + 4.4 < end:
        place(track, snore(1.9 + RNG.uniform(-0.2, 0.2)) * RNG.uniform(0.55, 0.8), cursor)
        place(track, breath(1.6, 0.04), cursor + 2.1)
        cursor += 4.5 + RNG.uniform(-0.3, 0.3)


def main() -> None:
    track = band_noise(int(DURATION * SAMPLE_RATE), 40, 6_000) * 0.004  # room tone
    quiet_breathing(track, 0, 12)
    snoring_bout(track, 12, 48)
    quiet_breathing(track, 48, 62)
    snoring_bout(track, 62, 84)
    quiet_breathing(track, 84, DURATION)
    track *= 0.7 / np.max(np.abs(track))
    pcm = (track * 32_767).astype(np.int16)

    with tempfile.TemporaryDirectory() as tmp:
        wav_path = pathlib.Path(tmp) / "sample.wav"
        with wave.open(str(wav_path), "wb") as wav:
            wav.setnchannels(1)
            wav.setsampwidth(2)
            wav.setframerate(SAMPLE_RATE)
            wav.writeframes(pcm.tobytes())
        OUTPUT.parent.mkdir(parents=True, exist_ok=True)
        subprocess.run(
            ["ffmpeg", "-y", "-loglevel", "error", "-i", str(wav_path), "-c:a", "aac", "-b:a", "48k", "-map_metadata", "-1", str(OUTPUT)],
            check=True,
        )
    print(f"Wrote {OUTPUT} ({OUTPUT.stat().st_size // 1024} KB)")


if __name__ == "__main__":
    main()
