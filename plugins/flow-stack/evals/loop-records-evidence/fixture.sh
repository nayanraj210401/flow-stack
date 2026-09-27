#!/usr/bin/env bash
set -e
. "$(dirname "$0")/../_lib/toy.sh"
toy_repo
toy_task mul "Add a mul function to the calculator." "No division."
toy_mul_check
toy_slice mul S1 todo "bash tests/test_mul.sh" "src/** tests/**"
