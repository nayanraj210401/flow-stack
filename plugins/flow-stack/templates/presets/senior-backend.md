# Preset: senior-backend
<!-- Applied by setup: frontmatter keys overwrite the template; Rules and Taste entries are appended with {{today}} replaced. -->

```yaml
attention: { review_minutes_per_day: 90, max_parallel_agents: 2 }
dojo: off
```

# Rules
- Never run migrations or touch shared infra without asking.

# Taste
## Code
- {{today}} · early returns over nested conditionals · src: preset senior-backend
- {{today}} · validate at boundaries (HTTP, queue, config); trust internal types · src: preset senior-backend
- {{today}} · no new dependency without naming the alternative considered · src: preset senior-backend
## Prose
- {{today}} · lead with the answer; no preamble · src: preset senior-backend
## Testing
- {{today}} · test behavior through public interfaces, not private helpers · src: preset senior-backend
- {{today}} · every bug fix ships with the regression check that reproduced it · src: preset senior-backend
