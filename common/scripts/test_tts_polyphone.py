#!/usr/bin/env python3
"""
多音字 TTS 測試腳本
策略：用佔位符繞過 edge-tts 的 XML escape，事後注入 phoneme 標籤。
"""

import asyncio
import re
from pathlib import Path
from xml.sax.saxutils import escape

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

# ── 已知多音字詞組對照（詞 → 字 → 注音）────────────────────
POLYPHONE_MAP = {
    "重要":   {"重": "ㄓㄨㄥˋ"},
    "比重":   {"重": "ㄓㄨㄥˋ"},
    "重啟":   {"重": "ㄔㄨㄥˊ"},
    "強調":   {"強": "ㄑㄧㄤˊ"},
    "強制":   {"強": "ㄑㄧㄤˊ"},
    "以和為貴": {"和": "ㄏㄜˊ"},
    "和談":   {"和": "ㄏㄜˊ"},
    "和平":   {"和": "ㄏㄜˊ"},
    "長者":   {"長": "ㄓㄤˇ"},
    "成長":   {"長": "ㄓㄤˇ"},
    "延長":   {"長": "ㄔㄤˊ"},
    "教練":   {"教": "ㄐㄧㄠˋ"},
    "些微差距": {"差": "ㄔㄚ"},
    "差距":   {"差": "ㄔㄚ"},
    "台中":   {"中": "ㄓㄨㄥ"},
    "中華":   {"中": "ㄓㄨㄥ"},
}

# 佔位符格式：不含任何 XML 特殊字元，escape 後原樣保留
PLACEHOLDER_RE = re.compile(r"PHONEME_([A-Za-z0-9]+)_([^_]+)_END")


def bopomofo_to_ascii_key(bopo: str) -> str:
    """把注音轉成純 ASCII key，避免佔位符內含非 ASCII 字元被誤處理。"""
    return bopo.encode("unicode_escape").decode("ascii").replace("\\", "U")


def ascii_key_to_bopomofo(key: str) -> str:
    return key.replace("U", "\\").encode("ascii").decode("unicode_escape")


def inject_placeholders(text: str) -> str:
    """將已知多音字詞組替換成佔位符（在 escape 之前）。"""
    # 依詞組長度降序，避免短詞覆蓋長詞
    for phrase in sorted(POLYPHONE_MAP, key=len, reverse=True):
        if phrase not in text:
            continue
        char_map = POLYPHONE_MAP[phrase]
        replacement = ""
        for ch in phrase:
            if ch in char_map:
                key = bopomofo_to_ascii_key(char_map[ch])
                replacement += f"PHONEME_{key}_{ch}_END"
            else:
                replacement += ch
        text = text.replace(phrase, replacement)
    return text


def placeholders_to_phoneme_tags(escaped_text: str) -> str:
    """escape 後，把佔位符還原成 SSML phoneme 標籤。"""
    def replacer(m):
        bopo = ascii_key_to_bopomofo(m.group(1))
        char = m.group(2)
        return f'<phoneme alphabet="bopo" ph="{bopo}">{char}</phoneme>'
    return PLACEHOLDER_RE.sub(replacer, escaped_text)


def patch_edge_tts_mkssml():
    """Monkey-patch edge_tts.communicate.mkssml，在 escape 後注入 phoneme 標籤。"""
    import edge_tts.communicate as ec

    original_mkssml = ec.mkssml

    def patched_mkssml(tc, escaped_text):
        if isinstance(escaped_text, bytes):
            escaped_text = escaped_text.decode("utf-8")
        escaped_text = placeholders_to_phoneme_tags(escaped_text)
        return original_mkssml(tc, escaped_text)

    ec.mkssml = patched_mkssml


async def generate_audio(text: str, output_path: Path, label: str):
    import edge_tts
    communicate = edge_tts.Communicate(text, voice="zh-TW-HsiaoChenNeural")
    await communicate.save(str(output_path))
    print(f"[{label}] 輸出：{output_path}")


async def main():
    out_dir = Path("/home/vboxuser/news-broadcast-system/common/tmp")
    out_dir.mkdir(parents=True, exist_ok=True)

    plain_out = out_dir / "test_plain.mp3"
    ssml_out  = out_dir / "test_ssml.mp3"

    # ── 1. 純文字版本（原始做法）
    print("產生純文字版本（原始 edge-tts）...")
    await generate_audio(TEST_TEXT, plain_out, "plain")

    # ── 2. SSML phoneme 版本
    print("\n產生 SSML phoneme 版本（佔位符注入）...")
    patch_edge_tts_mkssml()
    text_with_placeholders = inject_placeholders(TEST_TEXT)
    await generate_audio(text_with_placeholders, ssml_out, "ssml")

    print("\n完成！比較以下兩個檔案：")
    print(f"  純文字：{plain_out}")
    print(f"  SSML：  {ssml_out}")
    print("\n重點聆聽多音字：")
    print("  重（要/啟）、長（者/延長）、教（練）、和（談）、差（距）")


if __name__ == "__main__":
    asyncio.run(main())
