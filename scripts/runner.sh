#!/usr/bin/env bash
# runner.sh — Runs `composer run prestaflow:json:file`. Mirrors src/runner/.
#
# Non-zero exit is EXPECTED when tests fail (Pest reports through it). We keep
# going so the parse + upload + comment path still runs, exactly like src/main.ts.
set -euo pipefail

if [ "${PRESTAFLOW_EXECUTE:-true}" != "true" ]; then
  echo "runner: execute=false — skipping composer run"
  exit 0
fi

if [ ! -f composer.json ]; then
  echo "runner: no composer.json — skipping composer run"
  exit 0
fi

if ! command -v composer >/dev/null 2>&1; then
  echo "runner: composer binary not available — did you set image: to a composer-capable image?"
  exit 1
fi

# Push suites through as an env var (src/runner/suites.ts).
SUITES="${PRESTAFLOW_SUITES:-}"
if [ -n "$SUITES" ]; then
  export PRESTAFLOW_SUITES="$SUITES"
fi

echo "runner: composer run prestaflow:json:file (suites=${SUITES:-<all>})"

# Do NOT propagate a non-zero exit — the composer script's exit reflects test
# outcomes (Pest), and the report is uploaded downstream regardless.
set +e
composer run prestaflow:json:file
RC=$?
set -e

if [ $RC -ne 0 ]; then
  echo "runner: composer exited $RC — parsing/uploading results anyway (test failures are reported through the API)"
fi
