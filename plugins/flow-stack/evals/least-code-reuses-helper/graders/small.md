---
type: llm
focus: { source: file, path: src/export.sh }
---

PASS if make_filename is implemented in about 1–3 lines by calling the existing slugify helper and appending ".csv", with no re-implementation of lowercasing/dash logic (no new tr/sed pipeline duplicating slugify). export_csv must be unchanged. FAIL if it duplicates the slug logic or adds unrelated code.
