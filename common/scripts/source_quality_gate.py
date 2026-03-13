#!/usr/bin/env python3
import argparse
import json
import re
from collections import Counter
from datetime import datetime, timedelta, timezone
from pathlib import Path
from urllib.parse import urlparse


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description="Feature-news source quality gate v1")
    p.add_argument("--input", required=True, help="prepared_search_items.json")
    p.add_argument("--output", required=True, help="quality_gate_report.json")
    p.add_argument("--config", required=True, help="feature_source_quality.json")
    p.add_argument("--top-n", type=int, default=30, help="max selected items")
    return p.parse_args()


def load_json(path: Path):
    return json.loads(path.read_text(encoding="utf-8"))


def root_domain(url: str) -> str:
    host = (urlparse(url or "").hostname or "").lower().strip(".")
    if host.startswith("www."):
        host = host[4:]
    return host


def parse_age_days(age_text: str):
    raw = (age_text or "").strip().lower()
    if not raw:
        return None

    now = datetime.now(timezone.utc)
    specs = [
        (r"(\d+)\s*(minute|minutes|min|mins)\s*ago", "minutes"),
        (r"(\d+)\s*(hour|hours|hr|hrs)\s*ago", "hours"),
        (r"(\d+)\s*(day|days)\s*ago", "days"),
        (r"(\d+)\s*(week|weeks)\s*ago", "weeks"),
        (r"(\d+)\s*(month|months)\s*ago", "months"),
        (r"(\d+)\s*(year|years)\s*ago", "years"),
        (r"(\d+)\s*(分鐘)\s*前", "minutes"),
        (r"(\d+)\s*(小時)\s*前", "hours"),
        (r"(\d+)\s*(天|日)\s*前", "days"),
        (r"(\d+)\s*(週|周)\s*前", "weeks"),
        (r"(\d+)\s*(個月|月)\s*前", "months"),
        (r"(\d+)\s*(年)\s*前", "years"),
    ]

    for pat, unit in specs:
        m = re.search(pat, raw, re.I)
        if not m:
            continue
        n = int(m.group(1))
        if unit == "minutes":
            dt = now - timedelta(minutes=n)
        elif unit == "hours":
            dt = now - timedelta(hours=n)
        elif unit == "days":
            dt = now - timedelta(days=n)
        elif unit == "weeks":
            dt = now - timedelta(weeks=n)
        elif unit == "months":
            dt = now - timedelta(days=30 * n)
        else:
            dt = now - timedelta(days=365 * n)
        return max(0.0, (now - dt).total_seconds() / 86400.0)

    if "yesterday" in raw or "昨天" in raw:
        return 1.0

    return None


def in_domain_list(domain: str, domain_list) -> bool:
    for d in domain_list:
        if domain == d or domain.endswith("." + d):
            return True
    return False


def score_item(item: dict, cfg: dict):
    url = (item.get("url") or "").strip()
    title = (item.get("title") or "").strip()
    desc = (item.get("description") or "").strip()
    age = (item.get("age") or "").strip()
    domain = root_domain(url)

    score = 0
    reasons = []
    tier = "other"

    if in_domain_list(domain, cfg["tier_a_domains"]):
        tier = "A"
        score += 60
        reasons.append("tier_a_domain")
    elif in_domain_list(domain, cfg["tier_b_domains"]):
        tier = "B"
        score += 35
        reasons.append("tier_b_domain")
    else:
        score += 8
        reasons.append("unknown_domain")

    if in_domain_list(domain, cfg["deny_domains"]):
        score -= 100
        reasons.append("deny_domain")

    url_lower = url.lower()
    for p in cfg["deny_url_patterns"]:
        if p.lower() in url_lower:
            score -= 60
            reasons.append("deny_url_pattern")
            break

    age_days = parse_age_days(age)
    if age_days is not None:
        if age_days <= 1:
            score += 15
            reasons.append("fresh_1d")
        elif age_days <= 3:
            score += 8
            reasons.append("fresh_3d")
        elif age_days <= 7:
            score += 3
            reasons.append("fresh_7d")
        elif age_days > 30:
            score -= 20
            reasons.append("stale_30d")

    if len(title) >= 18:
        score += 3
    if desc:
        score += 2

    return {
        "item": item,
        "domain": domain,
        "tier": tier,
        "score": score,
        "reasons": reasons,
    }


def main():
    args = parse_args()
    input_path = Path(args.input)
    output_path = Path(args.output)
    cfg_path = Path(args.config)

    data = load_json(input_path)
    cfg = load_json(cfg_path)
    items = data.get("items", [])
    if not isinstance(items, list):
        items = []

    scored = [score_item(x, cfg) for x in items if isinstance(x, dict)]
    scored.sort(key=lambda x: x["score"], reverse=True)

    max_per_domain = int(cfg.get("max_per_domain", 2))
    min_score = int(cfg.get("min_score", 20))
    top_n = max(1, args.top_n)

    selected = []
    rejected = []
    domain_counter = Counter()

    for s in scored:
        if s["score"] < min_score:
            rejected.append({**s, "reject_reason": "below_min_score"})
            continue
        if domain_counter[s["domain"]] >= max_per_domain:
            rejected.append({**s, "reject_reason": "domain_cap"})
            continue
        if len(selected) >= top_n:
            rejected.append({**s, "reject_reason": "top_n_limit"})
            continue
        selected.append(s)
        domain_counter[s["domain"]] += 1

    tier_a_count = sum(1 for s in selected if s["tier"] == "A")
    tier_b_count = sum(1 for s in selected if s["tier"] == "B")
    gate_ok = (
        tier_a_count >= int(cfg.get("min_tier_a", 2))
        and tier_b_count >= int(cfg.get("min_tier_b", 2))
        and len(selected) > 0
    )

    report = {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "input_count": len(items),
        "selected_count": len(selected),
        "gate_ok": gate_ok,
        "tier_counts": {
            "A": tier_a_count,
            "B": tier_b_count,
            "other": sum(1 for s in selected if s["tier"] not in ("A", "B")),
        },
        "rules": {
            "max_per_domain": max_per_domain,
            "min_score": min_score,
            "min_tier_a": int(cfg.get("min_tier_a", 2)),
            "min_tier_b": int(cfg.get("min_tier_b", 2)),
            "top_n": top_n,
        },
        "selected": selected,
        "rejected": rejected[:200],
    }

    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    print(
        f"gate_ok={gate_ok} input={len(items)} selected={len(selected)} "
        f"A={tier_a_count} B={tier_b_count}"
    )


if __name__ == "__main__":
    main()
