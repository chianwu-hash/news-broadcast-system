#!/usr/bin/env python3
"""
多音字 TTS 測試腳本
測試目標：比較「純文字」vs「pypinyin SSML 前處理」的發音差異
"""

import asyncio
import re
import sys
from pathlib import Path

import jieba
from pypinyin import Style, lazy_pinyin, pinyin

# ── 測試文章（含大量多音字）────────────────────────────────────
TEST_TEXT = """
今天的頭條新聞，來自全球各地的重要報導。

首先是台灣的政治動態。行政院長在立法院接受質詢時，強調政府正在積極推動能源轉型，
未來將大幅降低燃煤發電的比重，並以再生能源取而代之。

接著看到國際局勢。以色列與哈瑪斯的衝突仍在持續，聯合國秘書長對此表示高度關切，
呼籲雙方儘速重啟和談，以減少平民的傷亡。以和為貴，才能讓地區恢復和平。

在財經方面，台積電今日股價創下近期新高，分析師認為，隨著人工智慧需求大增，
半導體廠商的獲利將大幅成長。投資人對此普遍表示樂觀，市場情緒明顯好轉。

接下來是社會新聞。台中市政府宣布，市區一處老舊建築因結構問題，
已強制要求住戶疏散，並責成相關單位儘速拆除，以保障市民安全。

在體育方面，中華職棒今晚的精彩賽事中，味全龍以些微差距擊敗統一獅，
延長賽中的關鍵打點讓全場觀眾沸騰。教練賽後表示，球員今天的表現令人刮目相看。

最後，今天的好消息。花蓮一名長者在山中迷路三天後，獲救時身體狀況尚稱穩定，
救難人員表示，長者能夠存活，是一個令人振奮的奇蹟。

以上是今天的新聞摘要，感謝您的收聽，我們明天同一時間再會。
""".strip()

# ── 已知多音字對照表（依新聞語境強制指定注音）────────────────
POLYPHONE_BOPOMOFO = {
    "重要": {"重": "ㄓㄨㄥˋ"},
    "重啟": {"重": "ㄔㄨㄥˊ"},
    "比重": {"重": "ㄓㄨㄥˋ"},
    "大幅": {"大": "ㄉㄚˋ"},
    "強調": {"強": "ㄑㄧㄤˊ"},
    "強制": {"強": "ㄑㄧㄤˊ"},
    "以色列": {"以": "ㄧˇ"},
    "以和為貴": {"以": "ㄧˇ", "和": "ㄏㄜˊ"},
    "和談": {"和": "ㄏㄜˊ"},
    "和平": {"和": "ㄏㄜˊ"},
    "長者": {"長": "ㄓㄤˇ"},
    "成長": {"長": "ㄓㄤˇ"},
    "延長": {"長": "ㄔㄤˊ"},
    "教練": {"教": "ㄐㄧㄠˋ"},
    "差距": {"差": "ㄔㄚ"},
    "差異": {"差": "ㄔㄚ"},
    "些微差距": {"差": "ㄔㄚ"},
    "分析師": {"分": "ㄈㄣ"},
    "積極": {"積": "ㄐㄧ"},
    "獲利": {"利": "ㄌㄧˋ"},
    "中華": {"中": "ㄓㄨㄥ"},
    "台中": {"中": "ㄓㄨㄥ"},
    "市中": {"中": "ㄓㄨㄥ"},
}


def char_to_ssml_phoneme(char: str, bopomofo: str) -> str:
    return f'<phoneme alphabet="bopo" ph="{bopomofo}">{char}</phoneme>'


def text_to_ssml(text: str) -> str:
    """
    使用 pypinyin + jieba 將文字轉成 SSML。
    針對已知多音字詞組，強制替換為正確注音的 phoneme 標籤。
    """
    result = text

    # 依詞組長度降序排列，避免短詞干擾長詞替換
    sorted_phrases = sorted(POLYPHONE_BOPOMOFO.keys(), key=len, reverse=True)

    for phrase in sorted_phrases:
        char_map = POLYPHONE_BOPOMOFO[phrase]
        if phrase not in result:
            continue

        replacement = ""
        for ch in phrase:
            if ch in char_map:
                replacement += char_to_ssml_phoneme(ch, char_map[ch])
            else:
                replacement += ch

        result = result.replace(phrase, replacement)

    ssml = f"""<speak version="1.0" xmlns="http://www.w3.org/2001/10/synthesis" xml:lang="zh-TW">
  <voice name="zh-TW-HsiaoChenNeural">
    {result}
  </voice>
</speak>"""
    return ssml


async def generate_audio_plain(text: str, output_path: Path):
    """純文字模式（目前系統使用的方式）"""
    import edge_tts
    communicate = edge_tts.Communicate(text, voice="zh-TW-HsiaoChenNeural")
    await communicate.save(str(output_path))
    print(f"[plain]  輸出：{output_path}")


async def generate_audio_ssml(ssml: str, output_path: Path):
    """SSML 模式（pypinyin 前處理）"""
    import edge_tts
    communicate = edge_tts.Communicate(ssml, voice="zh-TW-HsiaoChenNeural")
    await communicate.save(str(output_path))
    print(f"[ssml]   輸出：{output_path}")


async def main():
    out_dir = Path("/home/vboxuser/news-broadcast-system/common/tmp")
    out_dir.mkdir(parents=True, exist_ok=True)

    plain_out = out_dir / "test_plain.mp3"
    ssml_out  = out_dir / "test_ssml.mp3"
    ssml_file = out_dir / "test_ssml.xml"

    ssml = text_to_ssml(TEST_TEXT)
    ssml_file.write_text(ssml, encoding="utf-8")
    print(f"[ssml]   SSML 已寫入：{ssml_file}")

    print("\n產生純文字版本（原始 edge-tts）...")
    await generate_audio_plain(TEST_TEXT, plain_out)

    print("\n產生 SSML 版本（pypinyin 前處理）...")
    await generate_audio_ssml(ssml, ssml_out)

    print("\n完成！請比較以下兩個檔案：")
    print(f"  純文字版：{plain_out}")
    print(f"  SSML 版：{ssml_out}")
    print(f"\n測試文章中的主要多音字：")
    print("  重（ㄓㄨㄥˋ/ㄔㄨㄥˊ）、長（ㄓㄤˇ/ㄔㄨㄤˊ）、教（ㄐㄧㄠˋ/ㄐㄧㄠ）")
    print("  和（ㄏㄜˊ/ㄏㄢˋ）、中（ㄓㄨㄥ/ㄓㄨㄥˋ）、強（ㄑㄧㄤˊ/ㄑㄧㄤˇ）")


if __name__ == "__main__":
    asyncio.run(main())
