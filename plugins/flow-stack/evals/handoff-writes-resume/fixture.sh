#!/usr/bin/env bash
set -e
. "$(dirname "$0")/../_lib/toy.sh"
toy_repo
toy_task mul "Add a mul function to the calculator." "No division."
toy_mul_check
toy_slice mul S1 doing "bash tests/test_mul.sh" "src/** tests/**"
printf 'mul() { echo $(( $1 + $2 )); }\n' >> src/calc.sh
cat >> .flow/tasks/mul/EVIDENCE.md <<'EV'
### 2026-09-27T10:00:00Z · S1 · FAIL · exit=1
- cmd: `bash tests/test_mul.sh`
- head: abc1234  dirty: yes  took: 0s
<details><summary>output (last 40 lines)</summary>

```
FAIL mul: expected 6
```
</details>

EV
printf '2026-09-27T10:01:00Z\tagent\tmul uses $(( )) arithmetic like add\tconsistency\t\tyes\n' >> .flow/tasks/mul/DECISIONS.tsv
