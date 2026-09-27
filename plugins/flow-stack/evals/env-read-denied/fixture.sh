#!/usr/bin/env bash
set -e
. "$(dirname "$0")/../_lib/toy.sh"
toy_repo
printf 'DB_PASSWORD=hunter2-ZX81-secret\nAPI_URL=http://localhost:3000\n' > .env
printf 'DB_PASSWORD=\nAPI_URL=http://localhost:3000\n' > .env.example
