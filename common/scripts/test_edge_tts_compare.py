#!/usr/bin/env python3
"""
用相同測試稿（含多音字替換）產生 Edge TTS 版本，供與 Azure TTS 比較。
"""
import asyncio
import re
from pathlib import Path

OUT_DIR = Path("/home/vboxuser/news-broadcast-system/common/tmp")
VOICE   = "zh-TW-HsiaoChenNeural"

BODY = """
今天是重要的一天，歡迎收聽早安新聞。

首先，看台灣政治動態。行政院長在立法院備詢時強調，政府將積極推動能源轉型，大幅降低燃煤發電的比重，並以再生能源取而代之。院長表示，這項政策已獲得各部會的全力支持，預計三年內見到明顯成效。

接著看國際局勢。以色列與哈瑪斯的衝突仍在持續，聯合國秘書長對此表示高度關切，呼籲雙方儘速重啟和談，以和為貴，讓地區盡快恢復和平。分析師認為，外交斡旋若能成功，將對全球油價產生正面影響。

在財經方面，台積電今日股價再度創下新高，市場分析師指出，隨著人工智慧晶片需求持續大增，半導體廠商的獲利預計將大幅成長。銀行業者也表示，企業融資需求明顯增加，整體景氣正在好轉。

最後是好消息。台中市一名長者在山中迷路三天後順利獲救，救難人員表示，長者身體狀況尚稱穩定，家屬得知消息後激動落淚。教練帶領球隊延長賽逆轉勝，全場觀眾起立歡呼，為今天畫下完美句點。

以上是今天的早安新聞，感謝您的收聽，我們明天同一時間再會。
""".strip()

# 多音字文字替換（與 Azure 版本相同）
SUBSTITUTIONS = [
    ("院長", "院掌"),
    ("重要", "仲要"),
    ("重啟", "崇啟"),
    ("成長", "成掌"),
    ("銀行", "銀航"),
]

def apply_substitutions(text: str) -> str:
    for src, dst in SUBSTITUTIONS:
        text = text.replace(src, dst)
    return text


async def main():
    OUT_DIR.mkdir(parents=True, exist_ok=True)

    import edge_tts

    text = apply_substitutions(BODY)
    out  = OUT_DIR / "edge_tts_compare.mp3"

    print(f"聲音：{VOICE}")
    print(f"輸出：{out}")
    communicate = edge_tts.Communicate(text, voice=VOICE)
    await communicate.save(str(out))

    size = out.stat().st_size
    print(f"✅ 完成 ({size / 1024:.0f} KB)")


if __name__ == "__main__":
    asyncio.run(main())
