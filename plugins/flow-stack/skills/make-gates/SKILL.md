---
name: make-gates
description: "Forge .flow/gates.md: this repo's irreversible actions as deny/ask rules the guard hook enforces. /flow-stack:make-gates."
disable-model-invocation: true
---

# make-gates: know where the cliffs are

## Scan

- **Deploy**: CI/CD workflows, `fly.toml`, `vercel.json`, `railway.json`, `Procfile`, k8s manifests, Helm charts, and `deploy` scripts in package.json or the Makefile.
- **Data**: migration dirs, `prisma migrate`, `alembic`, `rails db:`, seed scripts that truncate, backup and restore scripts.
- **Infra**: Terraform, Pulumi, CDK, CloudFormation.
- **Money and outbound**: payment SDK calls in scripts, email or SMS senders, paid API CLIs.
- **Publishing**: `npm publish`, `cargo publish`, `twine upload`, docker push, app store uploads.
- **Shared state**: scripts that hit staging or prod URLs, and env names like `PROD_`.

## Write `.flow/gates.md` (from `../../templates/gates.md`)

Hook lines, matched as case-insensitive extended regex against Bash commands:

```
- deny: terraform[[:space:]]+destroy · destroys shared infra; never from an agent
- ask: terraform[[:space:]]+apply · changes shared infra
- ask: (prisma[[:space:]]+migrate[[:space:]]+deploy|alembic[[:space:]]+upgrade) · runs migrations against a real database
- ask: npm[[:space:]]+publish · publishes a package publicly
- ask: (fly|railway|vercel)[[:space:]]+(deploy|up|--prod) · deploys
```

Use `deny` only for actions that should never come from an agent. Everything else is `ask`, which makes the human confirm at that moment.

Below the hook lines, write prose gates for decisions that aren't commands ("changing the public API shape in openapi.yaml", "editing the billing module"). The `gate` skill reads these.

## Test

For each hook line, pipe a sample command through the guard hook (`echo '{"tool_input":{"command":"terraform apply"},"cwd":"'$PWD'"}' | <plugin>/hooks/guard.sh`) and confirm the decision. Also confirm that a harmless command (`terraform plan`) passes. Show the human the list for approval.
