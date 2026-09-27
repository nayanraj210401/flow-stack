# Preset: frontend-product
<!-- Applied by setup: frontmatter keys overwrite the template; Rules and Taste entries are appended with {{today}} replaced. -->

```yaml
attention: { review_minutes_per_day: 60, max_parallel_agents: 2 }
dojo: off
```

# Rules
- Every UI change is verified in a real browser with a screenshot in EVIDENCE.

# Taste
## Code
- {{today}} · colocate state with the component that owns it; lift only when shared · src: preset frontend-product
- {{today}} · no inline magic numbers for spacing or color; use tokens · src: preset frontend-product
## UI
- {{today}} · every async view has loading, empty, and error states · src: preset frontend-product
- {{today}} · keyboard reachable and visible focus on every control · src: preset frontend-product
## Prose
- {{today}} · UI copy: verbs on buttons, no "Click here" · src: preset frontend-product
## Testing
- {{today}} · prefer a user-level check (Playwright) over snapshot tests · src: preset frontend-product
