# Weekly KPI Review Loop

Use this loop every week to improve LDMS quality with real usage signals.

## KPI snapshot

Fetch from UI/API:
- `GET /api/kpis?project_id=<project>`

Track:
- helpful feedback count
- dissatisfaction count
- workflow success count
- top failure modes

## Top-5 failure review

1. Sort top failure modes by count.
2. Pick top 5 issues.
3. For each issue, define:
   - root cause hypothesis
   - patch owner
   - expected metric impact
4. Ship fixes behind feature flags when risky.
5. Re-measure next week.

## Quality gates

- `bundle exec rake test`
- `bundle exec rake eval`
- `bundle exec rake smoke`

No merge for risky changes unless all three pass.
