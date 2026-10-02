#!/usr/bin/env bash
# ecosystem.sh [dir]: what the repo is built with, so scenarios are written in its own
# language and run by a runner it already has. Prints one "key  value  (evidence)" line each:
#   ecosystem, pm, install, exec, runner, scenario, browser; then nested manifests (monorepos).
set -uo pipefail
r="${1:-.}"
has() { [ -e "$r/$1" ]; }
dep() { # dep <name>: declared in a root manifest
  grep -qsE "[\"' ]$1[\"'=<>~ \[]|^$1[=<>~ ]|^$1\$" "$r/package.json" "$r/pyproject.toml" "$r/requirements.txt" "$r/requirements-dev.txt" "$r/Gemfile" "$r/deno.json" 2>/dev/null
}
eco=""; pm=""; lock=""; install=""; exec=""; runner=""; scen=""; ev=""; browser=no

if has deno.json || has deno.jsonc; then
  eco=deno; ev=deno.json; pm=deno; install="deno install"; exec="deno run -A"
  runner="deno test -A"; scen="scenarios/<id>.test.ts"
elif has package.json; then
  eco=node; ev=package.json
  if has bun.lockb || has bun.lock; then pm=bun; lock=bun.lock; install="bun install --frozen-lockfile"; exec="bunx"
  elif has pnpm-lock.yaml; then pm=pnpm; lock=pnpm-lock.yaml; install="pnpm install --frozen-lockfile"; exec="pnpm exec"
  elif has yarn.lock; then pm=yarn; lock=yarn.lock; install="yarn install --frozen-lockfile"; exec="yarn"
  else pm=npm; lock=package-lock.json; install="npm ci"; exec="npx --no-install"; fi
  if [ "$pm" = bun ]; then runner="bun test"; scen="scenarios/<id>.test.ts"
  else runner="node --test"; scen="scenarios/<id>.test.mjs"; fi
  dep @playwright/test && browser=playwright
elif has pyproject.toml || has requirements.txt || has setup.py; then
  eco=python; ev="$(cd "$r" && ls pyproject.toml requirements.txt setup.py 2>/dev/null | head -1)"
  if has uv.lock; then pm=uv; lock=uv.lock; install="uv sync"; exec="uv run"
  elif has poetry.lock; then pm=poetry; lock=poetry.lock; install="poetry install"; exec="poetry run"
  else pm=pip; install="python -m pip install -r requirements.txt  # inside the repo's venv"; exec="python -m"; fi
  scen="scenarios/test_<id>.py"
  if dep pytest; then runner="$exec pytest -q"
  else runner="${exec%python -m} python -m unittest"; runner="${runner# }"; fi
  dep playwright && browser=playwright
elif has Gemfile; then
  eco=ruby; ev=Gemfile; pm=bundler; install="bundle install"; exec="bundle exec"
  if dep rspec; then runner="bundle exec rspec"; scen="scenarios/<id>_spec.rb"
  else runner="bundle exec ruby"; scen="scenarios/<id>_test.rb"; fi
else
  # Compiled or shell-native repos: drive the built binary or HTTP port from bash.
  if has go.mod; then eco=go; ev=go.mod; pm=go; install="go mod download"
  elif has Cargo.toml; then eco=rust; ev=Cargo.toml; pm=cargo; install="cargo fetch"
  elif has pom.xml; then eco=jvm; ev=pom.xml; pm=maven; install="mvn -q dependency:go-offline"
  elif has build.gradle || has build.gradle.kts; then eco=jvm; ev=build.gradle; pm=gradle; install="./gradlew dependencies"
  elif has mix.exs; then eco=elixir; ev=mix.exs; pm=mix; install="mix deps.get"
  elif ls "$r"/*.csproj "$r"/*.sln >/dev/null 2>&1; then eco=dotnet; ev="*.csproj"; pm=dotnet; install="dotnet restore"
  else # no manifest at the root: name the most common tracked source language
    top="$(git -C "$r" ls-files 2>/dev/null | grep -oE '\.(sh|py|js|mjs|ts|go|rs|rb)$' | cut -c2- | sort | uniq -c | sort -rn | head -1)"
    eco="$(echo "$top" | awk '{print $2}' | sed 's/^sh$/shell/;s/^py$/python/;s/^m\{0,1\}js$/node/;s/^ts$/node/;s/^rs$/rust/;s/^rb$/ruby/')"
    eco="${eco:-unknown}"; ev="${top:+most tracked files: .$(echo "$top" | awk '{print $2}')}"
  fi
  runner=bash; scen="scenarios/<id>.sh"
fi

line() { [ -n "$2" ] && printf '%-10s %s%s\n' "$1" "$2" "${3:+  ($3)}"; return 0; }
line ecosystem "$eco" "$ev"
line pm "$pm" "$lock"
line install "$install"
line exec "$exec"
line runner "$runner"
line scenario "$scen"
line browser "$browser"

# Monorepo: manifests below the root. Each deployable may need its own section.
find "$r" -maxdepth 3 \( -name node_modules -o -name '.?*' -o -name vendor -o -name target -o -name dist \) -prune -o \
  \( -name package.json -o -name pyproject.toml -o -name go.mod -o -name Cargo.toml -o -name Gemfile -o -name deno.json \) -print 2>/dev/null |
  sed "s|^$r/||" | grep / | sort | head -20 | while read -r m; do printf '%-10s %s\n' nested "$m"; done
