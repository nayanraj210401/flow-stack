---
id: {{id}}
title: {{title}}
owns: src/{{id}}/**
entries: web /path | api METHOD /path | cli command
scenario:
status: unverified
verified:
---
# {{title}}

<!-- One paragraph: what the user can do, in their words. No implementation details. -->

## Sub-features
<!-- One line each: "- {{id}}.<name> · <observable behavior>". Acceptance checks cite these IDs. -->
- {{id}}.main · 

## How to get to it
<!-- Every entry point a user can reach this from (UI path, URL, API route, CLI command, keyboard shortcut, deep link).
     A proof through one entry point is incomplete when others are listed here. -->

## Driving it
<!-- The exact steps the verify driver takes per entry point: commands, requests, clicks (by role/label).
     Point at the scenario script named in `scenario:`. -->

## Proof
<!-- The observable end state that proves it works: status code + body, screenshot of X, file written, row count.
     And one "must not happen" (absence) when the contract has one. -->

## Gotchas
<!-- Setup it needs (seed user, feature flag, env), flaky parts, things that look broken but aren't. -->
