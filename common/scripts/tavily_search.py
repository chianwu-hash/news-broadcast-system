#!/usr/bin/env python3
"""
tavily_search.py - Tavily News Search for feature-news

Usage:
    python3 tavily_search.py \
        --queries-file /path/to/queries.txt \
        --output /path/to/raw_search_results.json \
        --api-key tvly-xxxx \
        --program-name feature-news \
        --feature-scope global \
        --feature-profile trade_tariff \
        [--max-results 10] \
        [--search-depth basic]
"""

import argparse
import json
import sys
import urllib.error
import urllib.request
from datetime import datetime, timezone
from pathlib import Path
from urllib.parse import urlparse


def parse_args():
    p = argparse.ArgumentParser()
    p.add_argument("--queries-file", required=True)
    p.add_argument("--output", required=True)
    p.add_argument("--api-key", required=True)
    p.add_argument("--program-name", required=True)
    p.add_argument("--feature-scope", default="")
    p.add_argument("--feature-profile", default="")
    p.add_argument("--max-results", type=int, default=10)
    p.add_argument("--search-depth", default="basic", choices=["basic", "advanced"])
    p.add_argument("--days-back", type=int, default=None)
    return p.parse_args()


def tavily_search(
    query: str, api_key: str, max_results: int, search_depth: str, days_back: int | None
) -> dict:
    """Call Tavily API for a single query. Returns raw API response dict."""
    url = "https://api.tavily.com/search"
    payload_data = {
        "query": query,
        "topic": "news",
        "search_depth": search_depth,
        "max_results": max_results,
        "include_answer": False,
    }
    if days_back is not None:
        payload_data["days"] = days_back
    payload = json.dumps(payload_data).encode("utf-8")

    req = urllib.request.Request(
        url,
        data=payload,
        headers={
            "Content-Type": "application/json",
            "Authorization": f"Bearer {api_key}",
        },
        method="POST",
    )

    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            return json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        body = e.read().decode("utf-8", errors="replace")
        raise RuntimeError(f"Tavily HTTP {e.code}: {body[:500]}") from e


def normalize_to_brave_format(tavily_response: dict) -> dict:
    """
    Convert Tavily response to Brave Search response shape so downstream
    select_candidates.sh can process it without changes.
    """
    web_results = []
    for item in tavily_response.get("results", []):
        title = (item.get("title") or "").strip()
        url = (item.get("url") or "").strip()
        content = (item.get("content") or "").strip()
        published_date = (item.get("published_date") or "").strip()

        host = ""
        try:
            host = urlparse(url).hostname or ""
            if host.startswith("www."):
                host = host[4:]
        except Exception:
            host = ""

        web_results.append(
            {
                "title": title,
                "url": url,
                "description": content[:1000] if content else "",
                "age": published_date,
                "profile": {
                    "name": host,
                },
            }
        )

    return {"web": {"results": web_results}}


def main():
    args = parse_args()

    queries_path = Path(args.queries_file)
    if not queries_path.exists():
        print(f"[ERROR] queries file not found: {queries_path}", file=sys.stderr)
        sys.exit(1)

    queries = [line.strip() for line in queries_path.read_text(encoding="utf-8").splitlines() if line.strip()]
    if not queries:
        print("[ERROR] no queries found in queries file", file=sys.stderr)
        sys.exit(1)

    records = []
    for idx, query in enumerate(queries, start=1):
        print(f"[tavily] query_{idx}: {query}", file=sys.stderr)
        try:
            raw = tavily_search(query, args.api_key, args.max_results, args.search_depth, args.days_back)
            normalized = normalize_to_brave_format(raw)
            result_count = len(normalized["web"]["results"])
            print(f"[tavily] query_{idx}: got {result_count} results", file=sys.stderr)
        except Exception as e:
            print(f"[tavily] query_{idx} FAILED: {e}", file=sys.stderr)
            normalized = {"web": {"results": []}}

        records.append(
            {
                "query_index": idx,
                "query": query,
                "response": normalized,
            }
        )

    output = {
        "program_name": args.program_name,
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "search_engine": "tavily",
        "query_count": len(records),
        "feature_scope": args.feature_scope,
        "feature_profile": args.feature_profile,
        "days_back": args.days_back,
        "results": records,
    }

    output_path = Path(args.output)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(json.dumps(output, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"[tavily] done: {len(records)} queries -> {output_path}", file=sys.stderr)


if __name__ == "__main__":
    main()
