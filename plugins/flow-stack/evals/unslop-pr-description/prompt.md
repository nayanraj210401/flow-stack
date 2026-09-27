---
description: unslop rewrites an AI-sounding PR description into plain, specific prose.
max_turns: 4
allowed_tools: [Read, Skill]
---

Clean this PR description up with flow-stack's unslop. Keep every fact, lose the fluff. Reply with only the rewritten description, nothing before or after it.

"## 🚀 Overview
This PR delivers a comprehensive and robust enhancement to our caching layer, seamlessly leveraging Redis to elevate performance across the board. It's not just a speed boost, it's a paradigm shift in how we handle data!

## ✨ Changes
- Added a Redis cache in front of `getProduct()` with a 5-minute TTL
- Cache is invalidated when a product is updated via `updateProduct()`
- p95 latency for /products/:id went from 180ms to 35ms in staging

## 🙏 Notes
I hope this helps! Let me know if you have any questions. Note: cache stampede protection is not implemented yet."
