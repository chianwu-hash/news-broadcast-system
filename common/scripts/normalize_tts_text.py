#!/usr/bin/env python3
"""
normalize_tts_text.py
多音字正規化：將文字中的多音字替換成同音的無歧義字，讓 edge-tts 正確發音。

策略（雙層）：
  1. 詞組層級字典（優先）：直接替換已知有問題的詞組，不依賴 pypinyin
  2. 字元層級 pypinyin：處理字典未收錄的剩餘多音字

用法：
  python3 normalize_tts_text.py <input_txt> <output_txt>
"""

import re
import sys
from pathlib import Path

import jieba
from pypinyin import Style, pinyin

# ── Layer 1：詞組層級覆寫（最可靠，優先套用）────────────────────
# 格式：原詞 → 替換詞（替換字與原字同音但無歧義）
WORD_OVERRIDES: list[tuple[str, str]] = [
    # 重（ㄔㄨㄥˊ）
    ("重啟", "崇啟"),
    ("重建", "崇建"),
    ("重返", "崇返"),
    ("重新", "崇新"),
    ("重申", "崇申"),
    ("重演", "崇演"),
    ("重組", "崇組"),
    # 重（ㄓㄨㄥˋ）
    ("重要", "仲要"),
    ("重大", "仲大"),
    ("重點", "仲點"),
    ("比重", "比仲"),
    ("嚴重", "嚴仲"),
    ("重傷", "仲傷"),
    ("重量", "仲量"),
    # 行（ㄏㄤˊ）
    ("銀行", "銀航"),
    ("行業", "航業"),
    ("同行", "同航"),
    ("行情", "航情"),
    # 行（ㄒㄧㄥˊ）
    ("行政", "型政"),
    ("行為", "型為"),
    ("行動", "型動"),
    ("執行", "執型"),
    ("發行", "發型"),
    ("流行", "流型"),
    ("進行", "進型"),
    ("實行", "實型"),
    # 長（ㄓㄤˇ）
    ("院長", "院掌"),
    ("市長", "市掌"),
    ("部長", "部掌"),
    ("局長", "局掌"),
    ("校長", "校掌"),
    ("廳長", "廳掌"),
    ("縣長", "縣掌"),
    ("鄉長", "鄉掌"),
    ("會長", "會掌"),
    ("長官", "掌官"),
    ("成長", "成掌"),
    ("生長", "生掌"),
    # 長（ㄔㄤˊ）
    ("延長", "延腸"),
    ("增長", "增腸"),
    ("加長", "加腸"),
    # 強（ㄑㄧㄤˊ）
    ("強調", "牆調"),
    ("強制", "牆制"),
    ("強烈", "牆烈"),
    ("強大", "牆大"),
    ("強化", "牆化"),
    ("增強", "增牆"),
    ("加強", "加牆"),
    # 教（ㄐㄧㄠˋ）
    ("教練", "叫練"),
    ("教育", "叫育"),
    ("教師", "叫師"),
    ("教授", "叫授"),
    ("教學", "叫學"),
    # 差（ㄔㄚ）
    ("差距", "插距"),
    ("差異", "插異"),
    ("差別", "插別"),
    ("落差", "落插"),
    ("誤差", "誤插"),
    # 差（ㄔㄞ）
    ("出差", "出拆"),
    # 中（ㄓㄨㄥ）
    ("台中", "台鐘"),
    ("中華", "鐘華"),
    ("中國", "鐘國"),
    ("中央", "鐘央"),
    ("中東", "鐘東"),
    ("中間", "鐘間"),
    ("中文", "鐘文"),
    ("中共", "鐘共"),
    # 和（ㄏㄜˊ）
    ("和談", "何談"),
    ("和平", "何平"),
    ("和解", "何解"),
    ("和諧", "何諧"),
    ("以和為貴", "以何為貴"),
    # 分（ㄈㄣ）
    ("分析", "芬析"),
    ("分配", "芬配"),
    ("分裂", "芬裂"),
    # 分（ㄈㄣˋ）
    ("身分", "身份"),
    ("部分", "部份"),
    ("充分", "充份"),
]

# ── Layer 2：字元層級替換表（pypinyin 判斷正確時的補充）──────────
CHAR_SUBSTITUTE: dict[tuple[str, str], str] = {
    ("重", "zhong4"): "仲",
    ("重", "chong2"): "崇",
    ("長", "zhang3"): "掌",
    ("長", "chang2"): "腸",
    ("行", "xing2"):  "型",
    ("行", "hang2"):  "航",
    ("強", "qiang2"): "牆",
    ("強", "qiang3"): "搶",
    ("教", "jiao4"):  "叫",
    ("差", "cha1"):   "插",
    ("差", "chai1"):  "拆",
    ("中", "zhong1"): "鐘",
    ("中", "zhong4"): "眾",
    ("和", "he2"):    "何",
    ("分", "fen1"):   "芬",
    ("分", "fen4"):   "份",
}
POLYPHONE_CHARS = {ch for (ch, _) in CHAR_SUBSTITUTE}


def apply_word_overrides(text: str) -> str:
    """Layer 1：依詞組長度降序替換，避免短詞覆蓋長詞。"""
    for src, dst in sorted(WORD_OVERRIDES, key=lambda x: len(x[0]), reverse=True):
        text = text.replace(src, dst)
    return text


def apply_char_normalize(text: str) -> str:
    """Layer 2：用 jieba + pypinyin 處理字典未覆蓋的剩餘多音字。"""
    words = list(jieba.cut(text, cut_all=False))
    result = []
    for word in words:
        pinyins = pinyin(word, style=Style.TONE3, heteronym=False)
        new_word = []
        for ch, py_list in zip(word, pinyins):
            if ch in POLYPHONE_CHARS:
                py = py_list[0] if py_list else ""
                sub = CHAR_SUBSTITUTE.get((ch, py))
                new_word.append(sub if sub else ch)
            else:
                new_word.append(ch)
        result.append("".join(new_word))
    return "".join(result)


def normalize(text: str) -> str:
    text = apply_word_overrides(text)
    text = apply_char_normalize(text)
    return text


def main():
    if len(sys.argv) != 3:
        print(f"用法：{sys.argv[0]} <input_txt> <output_txt>")
        sys.exit(1)

    input_file  = Path(sys.argv[1])
    output_file = Path(sys.argv[2])

    if not input_file.exists():
        print(f"[ERROR] input not found: {input_file}")
        sys.exit(1)

    original = input_file.read_text(encoding="utf-8")
    normalized = normalize(original)
    output_file.write_text(normalized, encoding="utf-8")

    changes = sum(1 for a, b in zip(original, normalized) if a != b)
    print(f"[normalize] 替換 {changes} 個字元")


if __name__ == "__main__":
    main()
