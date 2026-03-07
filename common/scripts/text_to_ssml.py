#!/usr/bin/env python3
"""
text_to_ssml.py
將播報稿純文字轉換成 Azure TTS SSML。

功能：
- 段落間自動插入 <break> 停頓，讓語氣更自然
- XML escape 純文字內容
- 輸出完整 SSML 文件

注意：zh-TW-HsiaoChenNeural 不支援 <phoneme> 標籤，
      多音字由 Azure 神經網路依上下文自動判斷。

用法：
  python3 text_to_ssml.py <input_txt> <output_ssml> <voice_name>
"""

import re
import sys
from xml.sax.saxutils import escape
from pathlib import Path

# 段落間停頓時長（ms）
PARAGRAPH_BREAK_MS = 600
# 句末（。！？）停頓時長（ms）
SENTENCE_BREAK_MS = 300


def text_to_ssml(text: str, voice: str) -> str:
    """
    轉換純文字為 SSML：
    1. 以空行分段，段落間插入較長停頓
    2. 句末標點後插入短停頓
    3. 其餘文字 XML escape
    """
    paragraphs = [p.strip() for p in re.split(r"\n{2,}", text) if p.strip()]

    parts: list[str] = []
    for i, para in enumerate(paragraphs):
        if i > 0:
            parts.append(f'<break time="{PARAGRAPH_BREAK_MS}ms"/>')

        # 在句末標點後加短停頓
        processed = re.sub(
            r"([。！？])",
            lambda m: escape(m.group(1)) + f'<break time="{SENTENCE_BREAK_MS}ms"/>',
            escape(para),
        )
        parts.append(processed)

    body = "\n    ".join(parts)

    return (
        '<speak version="1.0" '
        'xmlns="http://www.w3.org/2001/10/synthesis" '
        'xml:lang="zh-TW">\n'
        f'  <voice name="{voice}">\n'
        f'    {body}\n'
        "  </voice>\n"
        "</speak>"
    )


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
