# Preset: data-ml
<!-- Applied by setup: frontmatter keys overwrite the template; Rules and Taste entries are appended with {{today}} replaced. -->

```yaml
attention: { review_minutes_per_day: 90, max_parallel_agents: 2 }
dojo: off
```

# Rules
- Never write to production tables or buckets; dry-run first and show row counts.

# Taste
## Code
- {{today}} · pipelines are idempotent: re-running a step converges to the same state · src: preset data-ml
- {{today}} · schemas are declared and validated at ingest · src: preset data-ml
## Testing
- {{today}} · a data change ships with a before/after count or distribution check · src: preset data-ml
- {{today}} · evals compare against a pinned baseline, never a vibe · src: preset data-ml
## Prose
- {{today}} · numbers carry units and sample size · src: preset data-ml
