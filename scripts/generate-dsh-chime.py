#!/usr/bin/env python3
"""生成内置提示音 `app/Resources/dsh-chime.wav`（只依赖 Python 标准库）。

设计目标（用户反馈「系统默认提示音太不明显」）：
- **更响**：峰值归一到 -0.7 dBFS（0.92），明显高于系统提示音常见的 0.4–0.6 峰值；
- **更有辨识度**：A5–C#6–E6 三音上行大调琶音，0.14s 一个，钟琴音色（基频 + 2/3/4.2 泛音）；
- **不刺耳**：4ms 起音、指数衰减、尾部 40ms 淡出，无爆音；
- 时长 ≈ 1.3s，单声道 44.1kHz / 16-bit PCM WAV（NSSound 原生支持）。

用法：
    python3 scripts/generate-dsh-chime.py            # 写默认位置
    python3 scripts/generate-dsh-chime.py out.wav    # 写到指定路径

改音色只需调 NOTE_STRIKES / PARTIALS / DECAY_TAU；重新生成后提交 wav 即可，
构建脚本 `scripts/build-app.sh` 只负责把 `app/Resources/` 拷进 .app。
"""

import math
import os
import struct
import sys
import wave

SAMPLE_RATE = 44_100
DURATION = 1.32
# (起始秒, 基频 Hz)
NOTE_STRIKES = [
    (0.00, 880.00),    # A5
    (0.14, 1108.73),   # C#6
    (0.28, 1318.51),   # E6
]
# (泛音倍频, 幅度) —— 钟琴/铃声的金属泛音分布（非整数倍泛音制造「铃」感）
PARTIALS = [
    (1.00, 1.00),
    (2.00, 0.36),
    (3.01, 0.15),
    (4.20, 0.075),
    (5.43, 0.035),
]
# 每个音的指数衰减时间常数（秒）；尾音相互叠成琶音
DECAY_TAU = 0.30
ATTACK_SECONDS = 0.004
# 一低八度的弱基频，给笔记本小喇叭一点「厚度」
SUB_OCTAVE_GAIN = 0.13
PEAK = 0.92


def synthesize() -> list[float]:
    total = int(SAMPLE_RATE * DURATION)
    buf = [0.0] * total
    for start, freq in NOTE_STRIKES:
        start_sample = int(start * SAMPLE_RATE)
        for i in range(start_sample, total):
            t = (i - start_sample) / SAMPLE_RATE
            env = math.exp(-t / DECAY_TAU)
            attack = 1.0 if t >= ATTACK_SECONDS else t / ATTACK_SECONDS
            value = 0.0
            for ratio, amp in PARTIALS:
                value += amp * math.sin(2.0 * math.pi * freq * ratio * t)
            value += SUB_OCTAVE_GAIN * math.sin(2.0 * math.pi * freq * 0.5 * t)
            buf[i] += value * env * attack
    return buf


def normalize(buf: list[float]) -> list[float]:
    peak = max(abs(x) for x in buf) or 1.0
    gain = PEAK / peak
    out = [x * gain for x in buf]
    fade = int(0.04 * SAMPLE_RATE)
    for i in range(fade):
        out[-1 - i] *= i / fade
    return out


def write_wav(path: str, samples: list[float]) -> None:
    frames = bytearray()
    for x in samples:
        frames += struct.pack("<h", max(-32768, min(32767, int(round(x * 32767)))))
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    with wave.open(path, "wb") as fh:
        fh.setnchannels(1)
        fh.setsampwidth(2)
        fh.setframerate(SAMPLE_RATE)
        fh.writeframes(bytes(frames))


def main(argv: list[str]) -> int:
    default = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "app", "Resources", "dsh-chime.wav")
    path = argv[1] if len(argv) > 1 else default
    samples = normalize(synthesize())
    write_wav(path, samples)
    peak = max(abs(x) for x in samples)
    rms = math.sqrt(sum(x * x for x in samples) / len(samples))
    print(f"wrote {os.path.normpath(path)}  {len(samples) / SAMPLE_RATE:.2f}s  "
          f"peak={peak:.3f}  rms={rms:.3f}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
