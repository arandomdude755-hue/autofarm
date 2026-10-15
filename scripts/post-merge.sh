#!/usr/bin/env bash
set -euo pipefail

python3 tools/bundle_customhub.py

for test_file in tests/check_*.py; do
    python3 "$test_file"
done
