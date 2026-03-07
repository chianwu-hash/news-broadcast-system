#!/usr/bin/env python3
"""
text_to_ssml.py
將播報稿純文字轉換成帶 phoneme 標籤的 Azure TTS SSML。

用法：
  python3 text_to_ssml.py <input_text_file> <output_ssml_file> <voice_name>
"""

import re
import sys
from pathlib import Path
from xml.sax.saxutils import escape

# ── 多音字詞組對照表（詞 → 字 → 注音）─────────────────────────
# 依新聞播報語境整理，日後可持續擴充
POLYPHONE_MAP: dict[str, dict[str, str]] = {
    # 重
    "重要":     {"重": "ㄓㄨㄥˋ"},
    "重大":     {"重": "ㄓㄨㄥˋ"},
    "重點":     {"重": "ㄓㄨㄥˋ"},
    "比重":     {"重": "ㄓㄨㄥˋ"},
    "重量":     {"重": "ㄓㄨㄥˋ"},
    "重傷":     {"重": "ㄓㄨㄥˋ"},
    "嚴重":     {"重": "ㄓㄨㄥˋ"},
    "重啟":     {"重": "ㄔㄨㄥˊ"},
    "重建":     {"重": "ㄔㄨㄥˊ"},
    "重返":     {"重": "ㄔㄨㄥˊ"},
    "重新":     {"重": "ㄔㄨㄥˊ"},
    "重申":     {"重": "ㄔㄨㄥˊ"},
    "重演":     {"重": "ㄔㄨㄥˊ"},
    # 長
    "長者":     {"長": "ㄓㄤˇ"},
    "成長":     {"長": "ㄓㄤˇ"},
    "生長":     {"長": "ㄓㄤˇ"},
    "院長":     {"長": "ㄓㄤˇ"},
    "市長":     {"長": "ㄓㄤˇ"},
    "部長":     {"長": "ㄓㄤˇ"},
    "局長":     {"長": "ㄓㄤˇ"},
    "校長":     {"長": "ㄓㄤˇ"},
    "長官":     {"長": "ㄓㄤˇ"},
    "延長":     {"長": "ㄔㄤˊ"},
    "加長":     {"長": "ㄔㄤˊ"},
    "增長":     {"長": "ㄔㄤˊ"},
    # 強
    "強調":     {"強": "ㄑㄧㄤˊ"},
    "強制":     {"強": "ㄑㄧㄤˊ"},
    "強烈":     {"強": "ㄑㄧㄤˊ"},
    "強大":     {"強": "ㄑㄧㄤˊ"},
    "強化":     {"強": "ㄑㄧㄤˊ"},
    "增強":     {"強": "ㄑㄧㄤˊ"},
    "加強":     {"強": "ㄑㄧㄤˊ"},
    "勉強":     {"強": "ㄑㄧㄤˇ"},
    # 和
    "和談":     {"和": "ㄏㄜˊ"},
    "和平":     {"和": "ㄏㄜˊ"},
    "和解":     {"和": "ㄏㄜˊ"},
    "和諧":     {"和": "ㄏㄜˊ"},
    "以和為貴": {"和": "ㄏㄜˊ"},
    # 教
    "教練":     {"教": "ㄐㄧㄠˋ"},
    "教育":     {"教": "ㄐㄧㄠˋ"},
    "教師":     {"教": "ㄐㄧㄠˋ"},
    "教授":     {"教": "ㄐㄧㄠˋ"},
    "教學":     {"教": "ㄐㄧㄠˋ"},
    "教導":     {"教": "ㄐㄧㄠˋ"},
    # 差
    "差距":     {"差": "ㄔㄚ"},
    "差異":     {"差": "ㄔㄚ"},
    "差別":     {"差": "ㄔㄚ"},
    "落差":     {"差": "ㄔㄚ"},
    "誤差":     {"差": "ㄔㄚ"},
    # 中
    "台中":     {"中": "ㄓㄨㄥ"},
    "中華":     {"中": "ㄓㄨㄥ"},
    "中國":     {"中": "ㄓㄨㄥ"},
    "中央":     {"中": "ㄓㄨㄥ"},
    "中間":     {"中": "ㄓㄨㄥ"},
    "中東":     {"中": "ㄓㄨㄥ"},
    "集中":     {"中": "ㄓㄨㄥ"},
    "打中":     {"中": "ㄓㄨㄥˋ"},
    "命中":     {"中": "ㄓㄨㄥˋ"},
    # 行
    "行政":     {"行": "ㄒㄧㄥˊ"},
    "行為":     {"行": "ㄒㄧㄥˊ"},
    "行動":     {"行": "ㄒㄧㄥˊ"},
    "執行":     {"行": "ㄒㄧㄥˊ"},
    "發行":     {"行": "ㄒㄧㄥˊ"},
    "銀行":     {"行": "ㄏㄤˊ"},
    "行業":     {"行": "ㄏㄤˊ"},
    "同行":     {"行": "ㄏㄤˊ"},
    # 分
    "分析":     {"分": "ㄈㄣ"},
    "分配":     {"分": "ㄈㄣ"},
    "分裂":     {"分": "ㄈㄣ"},
    "充分":     {"分": "ㄈㄣˋ"},
    "身分":     {"分": "ㄈㄣˋ"},
    "部分":     {"分": "ㄈㄣˋ"},
}


def build_replacement(phrase: str, char_map: dict[str, str]) -> str:
    """把詞組中的多音字包上 phoneme 標籤，其餘字 XML escape。"""
    result = ""
    for ch in phrase:
        if ch in char_map:
            bopo = char_map[ch]
            result += f'<phoneme alphabet="bopo" ph="{bopo}">{escape(ch)}</phoneme>'
        else:
            result += escape(ch)
    return result


def text_to_ssml(text: str, voice: str) -> str:
    """
    1. 依詞組長度降序，把已知多音字詞組替換成 phoneme 標籤。
    2. 其餘文字做 XML escape。
    3. 包成完整 SSML。
    """
    # 標記已被替換的區域，避免重複處理
    # 做法：先把詞組換成佔位符，再 escape 其餘文字，最後還原標籤
    MARK_START = "\x00PHONEME:"
    MARK_END   = ":PHONEME\x00"
    replacements: list[str] = []

    for phrase in sorted(POLYPHONE_MAP, key=len, reverse=True):
        if phrase not in text:
            continue
        char_map = POLYPHONE_MAP[phrase]
        tag = build_replacement(phrase, char_map)
        idx = len(replacements)
        replacements.append(tag)
        text = text.replace(phrase, f"{MARK_START}{idx}{MARK_END}")

    # escape 其餘純文字部分
    parts = re.split(r"(\x00PHONEME:\d+:PHONEME\x00)", text)
    processed = []
    for part in parts:
        m = re.fullmatch(r"\x00PHONEME:(\d+):PHONEME\x00", part)
        if m:
            processed.append(replacements[int(m.group(1))])
        else:
            processed.append(escape(part))

    body = "".join(processed)

    ssml = (
        '<speak version="1.0" '
        'xmlns="http://www.w3.org/2001/10/synthesis" '
        'xml:lang="zh-TW">\n'
        f'  <voice name="{voice}">\n'
        f'    {body}\n'
        "  </voice>\n"
        "</speak>"
    )
    return ssml


def main():
    if len(sys.argv) != 4:
        print(f"用法：{sys.argv[0]} <input_txt> <output_ssml> <voice_name>")
        sys.exit(1)

    input_file  = Path(sys.argv[1])
    output_file = Path(sys.argv[2])
    voice       = sys.argv[3]

    if not input_file.exists():
        print(f"[ERROR] input file not found: {input_file}")
        sys.exit(1)

    text = input_file.read_text(encoding="utf-8").strip()
    if not text:
        print(f"[ERROR] input file is empty: {input_file}")
        sys.exit(1)

    ssml = text_to_ssml(text, voice)
    output_file.write_text(ssml, encoding="utf-8")
    print(f"[text_to_ssml] done → {output_file} ({len(ssml)} chars)")


if __name__ == "__main__":
    main()
