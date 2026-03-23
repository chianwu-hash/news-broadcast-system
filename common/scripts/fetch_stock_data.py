#!/usr/bin/env python3
"""
fetch_stock_data.py — 抓台股大盤 (^TWII) + 台積電 (2330.TW) 收盤資料
輸出 JSON，供 write_script.sh 注入撰稿 prompt

退出碼：
  0 — 成功，JSON 印到 stdout
  1 — 市場今天未開市（週末或假日）
  2 — 抓取失敗
"""
import json
import sys
import urllib.request
import urllib.error
from datetime import datetime, timezone, timedelta

VOLATILITY_THRESHOLD = 1.5  # 漲跌超過此 % 視為劇烈震盪
TWSE_TIMEZONE = timezone(timedelta(hours=8))  # UTC+8

SYMBOLS = {
    "twii": "^TWII",
    "tsmc": "2330.TW",
}

HEADERS = {
    "User-Agent": "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36",
    "Accept": "application/json",
}


def fetch_yahoo(symbol: str) -> dict:
    url = (
        f"https://query1.finance.yahoo.com/v8/finance/chart/{symbol}"
        f"?interval=1d&range=2d&includePrePost=false"
    )
    req = urllib.request.Request(url, headers=HEADERS)
    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            data = json.loads(resp.read().decode("utf-8"))
    except urllib.error.URLError as e:
        raise RuntimeError(f"fetch failed for {symbol}: {e}")

    result = data.get("chart", {}).get("result")
    if not result:
        error = data.get("chart", {}).get("error", {})
        raise RuntimeError(f"no result for {symbol}: {error}")

    meta = result[0].get("meta", {})
    timestamps = result[0].get("timestamp", [])
    closes = result[0].get("indicators", {}).get("quote", [{}])[0].get("close", [])

    if len(closes) < 2 or len(timestamps) < 2:
        raise RuntimeError(f"insufficient data for {symbol}: closes={closes}")

    # 最新一筆（今天收盤）
    latest_close = closes[-1]
    prev_close = closes[-2]

    if latest_close is None or prev_close is None:
        raise RuntimeError(f"null close for {symbol}")

    change_pct = ((latest_close - prev_close) / prev_close) * 100

    # 確認最新資料是今天的（台灣時間）
    latest_ts = timestamps[-1]
    latest_date = datetime.fromtimestamp(latest_ts, tz=TWSE_TIMEZONE).strftime("%Y-%m-%d")
    today = datetime.now(TWSE_TIMEZONE).strftime("%Y-%m-%d")

    return {
        "price": round(latest_close, 2),
        "prev_price": round(prev_close, 2),
        "change": round(latest_close - prev_close, 2),
        "change_pct": round(change_pct, 2),
        "data_date": latest_date,
        "is_today": latest_date == today,
        "currency": meta.get("currency", "TWD"),
    }


def is_market_day() -> bool:
    """台股週一至週五開市（簡易判斷，不含國定假日）"""
    now = datetime.now(TWSE_TIMEZONE)
    return now.weekday() < 5  # 0=週一, 4=週五


def main():
    if not is_market_day():
        print(json.dumps({"market_open": False, "reason": "weekend"}, ensure_ascii=False))
        sys.exit(1)

    try:
        twii = fetch_yahoo(SYMBOLS["twii"])
        tsmc = fetch_yahoo(SYMBOLS["tsmc"])
    except RuntimeError as e:
        print(json.dumps({"market_open": False, "reason": str(e)}, ensure_ascii=False))
        sys.exit(2)

    # 如果抓到的資料不是今天，可能是假日補班等情況
    if not twii["is_today"]:
        print(json.dumps({
            "market_open": False,
            "reason": f"latest data is {twii['data_date']}, not today"
        }, ensure_ascii=False))
        sys.exit(1)

    is_volatile = abs(twii["change_pct"]) >= VOLATILITY_THRESHOLD

    result = {
        "market_open": True,
        "date": twii["data_date"],
        "twii": {
            "index": twii["price"],
            "change": twii["change"],
            "change_pct": twii["change_pct"],
            "direction": "上漲" if twii["change"] >= 0 else "下跌",
        },
        "tsmc": {
            "price": tsmc["price"],
            "change": tsmc["change"],
            "change_pct": tsmc["change_pct"],
            "direction": "上漲" if tsmc["change"] >= 0 else "下跌",
        },
        "is_volatile": is_volatile,
        "volatility_threshold_pct": VOLATILITY_THRESHOLD,
    }

    print(json.dumps(result, ensure_ascii=False, indent=2))
    sys.exit(0)


if __name__ == "__main__":
    main()
