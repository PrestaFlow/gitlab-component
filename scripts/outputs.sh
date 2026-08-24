#!/usr/bin/env bash
# outputs.sh — Writes prestaflow.env with the final counts. GitLab exposes this
# file via `artifacts:reports:dotenv`, so downstream jobs that declare
#   needs: [{ job: prestaflow, artifacts: true }]
# see PRESTAFLOW_* as environment variables. Mirrors src/reporter/outputs.ts.
#
# upload.sh has already appended PRESTAFLOW_REPORT_{ID,URL}; flashlight.sh
# appends PRESTAFLOW_FO_URL / PRESTAFLOW_PS_VERSION when it ran. We only add
# the counters + status here.
set -euo pipefail

RESULTS=""
for c in tests/prestaflow/results.json prestaflow/results.json; do
  if [ -f "$c" ]; then RESULTS="$c"; break; fi
done

if [ -n "$RESULTS" ]; then
  STATS=$(jq '
    def tonum(x): (x // 0 | tonumber? // 0);
    def acc(s):
      { passed: (s.stats.passes | tonum(.)),
        failed: (s.stats.failures | tonum(.)),
        skipped: ((s.stats.skips | tonum(.)) + (s.stats.skippeds | tonum(.))),
        todos: (s.stats.todos | tonum(.)),
        durationMs: (s.stats.time | tonum(.)) };
    (if (.suites | type == "array") then [ .suites[] | acc(.) ]
     elif .stats then [ acc(.) ]
     else [] end)
    | { passed: [.[].passed] | add // 0,
        failed: [.[].failed] | add // 0,
        skipped: [.[].skipped] | add // 0,
        todos: [.[].todos] | add // 0,
        durationMs: [.[].durationMs] | add // 0 }
    | .total = (.passed + .failed + .skipped + .todos)
  ' "$RESULTS")
else
  STATS='{"passed":0,"failed":0,"skipped":0,"total":0,"durationMs":0}'
  echo "outputs: no results.json — writing zero counters"
fi

PASSED=$(echo "$STATS" | jq -r '.passed')
FAILED=$(echo "$STATS" | jq -r '.failed')
SKIPPED=$(echo "$STATS" | jq -r '.skipped')
TOTAL=$(echo "$STATS" | jq -r '.total')
DURATION_MS=$(echo "$STATS" | jq -r '.durationMs')

STATUS="success"
[ "$FAILED" != "0" ] && STATUS="failure"

{
  echo "PRESTAFLOW_PASSED=${PASSED}"
  echo "PRESTAFLOW_FAILED=${FAILED}"
  echo "PRESTAFLOW_SKIPPED=${SKIPPED}"
  echo "PRESTAFLOW_TOTAL=${TOTAL}"
  echo "PRESTAFLOW_DURATION_MS=${DURATION_MS}"
  echo "PRESTAFLOW_STATUS=${STATUS}"
} >> prestaflow.env

echo "outputs: total=${TOTAL} passed=${PASSED} failed=${FAILED} skipped=${SKIPPED} status=${STATUS}"

# Match the GitHub Action: mark the job as failed when tests failed. This runs
# after upload + MR comment, so the report is delivered before the job errors out.
if [ "$FAILED" != "0" ]; then
  echo "outputs: ${FAILED} test(s) failed — exiting non-zero"
  exit 1
fi
