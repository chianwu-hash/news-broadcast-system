#!/usr/bin/env python3
"""
normalize_tts_text.py
使用 jieba + pypinyin 自動偵測多音字，並替換成同音的無歧義字，
讓 edge-tts 正確發音。

用法：
  python3 normalize_tts_text.py <input_txt> <output_txt>
"""

import sys
from pathlib import Path

import jieba
from pypinyin import Style, pinyin

# ── 替換表：(多音字, 正確拼音_含聲調數字) → 無歧義同音字 ───────
# 只列新聞播報情境中常見的多音字
SUBSTITUTE: dict[tuple[str, str], str] = {
    # 重
    ("重", "zhong4"): "仲",   # 重要、比重、嚴重
    ("重", "chong2"): "崇",   # 重啟、重建、重新
    # 長
    ("長", "zhang3"): "掌",   # 院長、市長、部長、成長
    ("長", "chang2"): "腸",   # 延長、增長、加長
    # 行
    ("行", "xing2"): "型",    # 行政、行為、行動、執行
    ("行", "hang2"): "航",    # 銀行、行業、同行
    # 強
    ("強", "qiang2"): "牆",   # 強調、強烈、強化、加強
    ("強", "qiang3"): "搶",   # 勉強（口語）
    # 教
    ("教", "jiao4"): "叫",    # 教練、教育、教師
    ("教", "jiao1"): "交",    # 教書（較少見）
    # 差
    ("差", "cha1"): "插",     # 差距、差異、落差
    ("差", "cha4"): "岔",     # 差勁（較少見）
    ("差", "chai1"): "拆",    # 出差
    # 中
    ("中", "zhong1"): "鐘",   # 台中、中華、中央、中東
    ("中", "zhong4"): "眾",   # 命中、打中
    # 和
    ("和", "he2"): "何",      # 和平、和談、和解
    ("和", "huo2"): "活",     # 和麵（較少見）
    # 分
    ("分", "fen1"): "芬",     # 分析、分配、分裂
    ("分", "fen4"): "份",     # 身分、部分、充分
    # 得
    ("得", "de2"): "德",      # 得到、獲得
    # 發
    ("發", "fa1"): "花",      # 發展、發表、發現  -- 花 fa1? No, 花 is hua1
    # 號
    ("號", "hao4"): "好",     # 號碼 -- wait 好 is hao3/hao4
    # 樂
    ("樂", "le4"): "勒",      # 音樂... 勒 is le4/lei4, not ideal
    ("樂", "yue4"): "越",     # 音樂
}

# 移除可能有問題的條目，只保留確定正確的
SUBSTITUTE = {
    ("重", "zhong4"): "仲",
    ("重", "chong2"): "崇",
    ("長", "zhang3"): "掌",
    ("長", "chang2"): "腸",
    ("行", "xing2"): "型",
    ("行", "hang2"): "航",
    ("強", "qiang2"): "牆",
    ("強", "qiang3"): "搶",
    ("教", "jiao4"): "叫",
    ("差", "cha1"): "插",
    ("差", "chai1"): "拆",
    ("中", "zhong1"): "鐘",
    ("中", "zhong4"): "眾",
    ("和", "he2"): "何",
    ("分", "fen1"): "芬",
    ("分", "fen4"): "份",
}

# 需要處理的多音字集合（快速判斷用）
POLYPHONE_CHARS = {ch for (ch, _) in SUBSTITUTE}


def normalize(text: str) -> str:
    """
    1. jieba 斷詞
    2. 對每個詞用 pypinyin 取得上下文正確讀音
    3. 若 (字, 拼音) 在替換表中，替換成無歧義同音字
    """
    words = list(jieba.cut(text, cut_all=False))
    result = []

    for word in words:
        # 取得該詞每個字的上下文拼音（TONE3：帶數字聲調，如 zhong4）
        pinyins = pinyin(word, style=Style.TONE3, heteronym=False)

        new_word = []
        for ch, py_list in zip(word, pinyins):
            if ch in POLYPHONE_CHARS:
                py = py_list[0] if py_list else ""
                substitute = SUBSTITUTE.get((ch, py))
                new_word.append(substitute if substitute else ch)
            else:
                new_word.append(ch)

        result.append("".join(new_word))

    return "".join(result)


def main():
    if len(sys.argv) != 3:
        print(f"用法：{sys.argv[0]} <input_txt> <output_txt>")
        sys.exit(1)

    input_file  = Path(sys.argv[1])
    output_file = Path(sys.argv[2])

    if not input_file.exists():
        print(f"[ERROR] input not found: {input_file}")
        sys.exit(1)

    text = input_file.read_text(encoding="utf-8")
    normalized = normalize(text)
    output_file.write_text(normalized, encoding="utf-8")

    # 印出被替換的字供確認
    changes = []
    for i, (orig, norm) in enumerate(zip(text, normalized)):
        if orig != norm:
            changes.append(f"{orig}→{norm}")
    if changes:
        print(f"[normalize] 替換 {len(changes)} 處：{'、'.join(changes[:20])}")
    else:
        print("[normalize] 無需替換")


if __name__ == "__main__":
    main()
