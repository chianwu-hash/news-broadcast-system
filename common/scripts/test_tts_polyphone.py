#!/usr/bin/env python3
"""
多音字 TTS 測試腳本
逐步診斷 edge-tts SSML 注入是否生效。
"""

import asyncio
from pathlib import Path

import edge_tts
import edge_tts.communicate as ec

OUT_DIR = Path("/home/vboxuser/news-broadcast-system/common/tmp")
VOICE   = "zh-TW-HsiaoChenNeural"

SHORT_TEXT = "今天是重要的一天，政府將重啟和談，長者表示樂觀，延長賽也很精彩。"

_original_mkssml = ec.mkssml
_transform_fn = None

def patched_mkssml(tc, escaped_text):
    if isinstance(escaped_text, bytes):
        escaped_text = escaped_text.decode("utf-8")
    if _transform_fn:
        escaped_text = _transform_fn(escaped_text)
    result = _original_mkssml(tc, escaped_text)
    # 印出實際送出的 SSML 供 debug
    print(f"    [SSML sent]:\n{result[:400]}\n")
    return result

ec.mkssml = patched_mkssml


async def run(label: str, text: str, filename: str, transform=None):
    global _transform_fn
    _transform_fn = transform
    output = OUT_DIR / filename
    try:
        communicate = edge_tts.Communicate(text, voice=VOICE)
        await communicate.save(str(output))
        size = output.stat().st_size
        print(f"  ✅ [{label}] {filename} ({size} bytes)")
        return True
    except Exception as e:
        print(f"  ❌ [{label}] 失敗：{e}")
        return False


async def main():
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    print("=" * 55)
    print("診斷：edge-tts SSML 注入")
    print("=" * 55)

    # 1. 純文字 baseline
    await run("1_plain", SHORT_TEXT, "diag_1_plain.mp3")

    # 2. 注入 <break>
    def add_break(t):
        return t.replace("重要的一天，", '重要的一天，<break time="600ms"/>')
    await run("2_break", SHORT_TEXT, "diag_2_break.mp3", transform=add_break)

    # 3. 注入 phoneme（拼音）
    def add_phoneme_pinyin(t):
        return t.replace(
            "重要",
            '<phoneme alphabet="zh-latn-pinyin" ph="zhong4 yao4">重要</phoneme>'
        )
    await run("3_phoneme_pinyin", SHORT_TEXT, "diag_3_phoneme.mp3", transform=add_phoneme_pinyin)

    print("\n完成！")


if __name__ == "__main__":
    asyncio.run(main())
