#!/usr/bin/env bash
set -e
. "$(dirname "$0")/../_lib/toy.sh"
toy_repo
mkdir -p infra prisma/migrations/001_init .github/workflows
printf 'resource "aws_s3_bucket" "assets" { bucket = "acme-assets" }\n' > infra/main.tf
printf 'CREATE TABLE users (id int);\n' > prisma/migrations/001_init/migration.sql
printf 'datasource db { provider = "postgresql" url = env("DATABASE_URL") }\n' > prisma/schema.prisma
printf '{ "name": "calc", "scripts": { "deploy": "fly deploy", "migrate": "prisma migrate deploy", "release": "npm publish" } }\n' > package.json
printf 'name: deploy\non: { push: { branches: [main] } }\njobs: { deploy: { runs-on: ubuntu-latest, steps: [ { run: "fly deploy --remote-only" } ] } }\n' > .github/workflows/deploy.yml
git add -A && git commit -qm "infra"
