#!/usr/bin/env python3
"""
多音字 TTS 測試腳本
診斷 edge-tts 對各種 SSML 標籤的支援程度。
"""

import asyncio
from pathlib import Path

OUT_DIR = Path("/home/vboxuser/news-broadcast-system/common/tmp")
VOICE   = "zh-TW-HsiaoChenNeural"

TEST_TEXT = (
    "今天的頭條新聞，來自全球各地的重要報導。"
    "行政院長強調，政府將積極推動能源轉型，降低燃煤發電的比重。"
    "以色列與哈瑪斯的衝突仍在持續，聯合國呼籲雙方儘速重啟和談。"
    "分析師認為，隨著人工智慧需求大增，半導體廠商的獲利將大幅成長。"
    "台中市一名長者在山中迷路三天後獲救，延長賽中教練表示非常振奮。"
)

PLACEHOLDER = "XPHONEME"

def patch_mkssml(transform_fn):
    """Monkey-patch edge_tts.communicate.mkssml，在 escape 後套用 transform_fn。"""
    import edge_tts.communicate as ec
    original = ec.mkssml
    def patched(tc, escaped_text):
        if isinstance(escaped_text, bytes):
            escaped_text = escaped_text.decode("utf-8")
        escaped_text = transform_fn(escaped_text)
        return original(tc, escaped_text)
    ec.mkssml = patched

def restore_mkssml():
    """還原原始 mkssml（重新 import）。"""
    import importlib
    import edge_tts.communicate as ec
    importlib.reload(ec)


async def test_case(label: str, text: str, output_path: Path, transform_fn=None):
    """執行單一測試，transform_fn 在 escape 後對 escaped_text 做變換。"""
    import importlib
    import edge_tts.communicate as ec
    importlib.reload(ec)  # 每次重置 patch

    if transform_fn:
        patch_mkssml(transform_fn)

    import edge_tts
    importlib.reload(edge_tts)

    try:
        communicate = edge_tts.Communicate(text, voice=VOICE)
        await communicate.save(str(output_path))
        size = output_path.stat().st_size
        print(f"  ✅ [{label}] 成功 → {output_path.name} ({size} bytes)")
        return True
    except Exception as e:
        print(f"  ❌ [{label}] 失敗：{e}")
        return False


async def main():
    OUT_DIR.mkdir(parents=True, exist_ok=True)

    print("=" * 55)
    print("診斷測試：edge-tts SSML 標籤支援程度")
    print("=" * 55)

    # ── Case 1：純文字（baseline）
    await test_case(
        "1_plain",
        TEST_TEXT,
        OUT_DIR / "test_1_plain.mp3",
    )

    # ── Case 2：注入 <break>（最基本的 SSML，幾乎一定支援）
    def inject_break(escaped_text: str) -> str:
        return escaped_text.replace(
            "重要報導。",
            '重要報導。<break time="800ms"/>'
        )
    await test_case(
        "2_break_tag",
        TEST_TEXT,
        OUT_DIR / "test_2_break.mp3",
        transform_fn=inject_break,
    )

    # ── Case 3：phoneme 用拼音（zh-latn-pinyin）
    def inject_phoneme_pinyin(escaped_text: str) -> str:
        # 重要 → zhòng yào
        return escaped_text.replace(
            "重要",
            '<phoneme alphabet="zh-latn-pinyin" ph="zhòng yào">重要</phoneme>'
        )
    await test_case(
        "3_phoneme_pinyin",
        TEST_TEXT,
        OUT_DIR / "test_3_phoneme_pinyin.mp3",
        transform_fn=inject_phoneme_pinyin,
    )

    # ── Case 4：phoneme 用注音（bopo）
    def inject_phoneme_bopo(escaped_text: str) -> str:
        return escaped_text.replace(
            "重要",
            '<phoneme alphabet="bopo" ph="ㄓㄨㄥˋ ㄧㄠˋ">重要</phoneme>'
        )
    await test_case(
        "4_phoneme_bopo",
        TEST_TEXT,
        OUT_DIR / "test_4_phoneme_bopo.mp3",
        transform_fn=inject_phoneme_bopo,
    )

    # ── Case 5：<sub> 替換（用同音但無歧義的字替代顯示）
    def inject_sub(escaped_text: str) -> str:
        # 直接用文字替換讓 TTS 念替代詞，不依賴 phoneme
        return escaped_text.replace(
            "重要",
            '<sub alias="仲要">重要</sub>'
        )
    await test_case(
        "5_sub_alias",
        TEST_TEXT,
        OUT_DIR / "test_5_sub.mp3",
        transform_fn=inject_sub,
    )

    print("\n完成！請聆聽各檔案，確認哪些 SSML 標籤有作用。")
    print(f"輸出目錄：{OUT_DIR}")


if __name__ == "__main__":
    asyncio.run(main())
