# Feature News Source Quality V1

## Goal
Build a source-governance layer before feature script generation.

## Policy
- Tier A: official or primary sources.
- Tier B: established mainstream media/wire services.
- Other: allowed but lower trust.
- Deny: blocked domains/patterns.

## Current Files
- Config: `/home/vboxuser/news-broadcast-system/common/config/feature_source_quality.json`
- Scorer: `/home/vboxuser/news-broadcast-system/common/scripts/source_quality_gate.py`

## Suggested Integration
1. Run normal `search_news` and preparation first.
2. Execute source gate:
   - input: `feature-news/output/prepared_search_items.json`
   - output: `feature-news/output/source_quality_report.json`
3. If `gate_ok=false`, stop script generation and notify Telegram with reason.
4. If `gate_ok=true`, use `selected[].item` as input for feature outline/script.

## Command Example
```bash
python3 /home/vboxuser/news-broadcast-system/common/scripts/source_quality_gate.py \
  --input /home/vboxuser/news-broadcast-system/feature-news/output/prepared_search_items.json \
  --output /home/vboxuser/news-broadcast-system/feature-news/output/source_quality_report.json \
  --config /home/vboxuser/news-broadcast-system/common/config/feature_source_quality.json \
  --top-n 30
```

## V1 Acceptance
- `selected_count > 0`
- `tier_counts.A >= 2`
- `tier_counts.B >= 2`
- No blocked domain in `selected`
