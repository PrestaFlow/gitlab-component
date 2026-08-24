#!/usr/bin/env bash
# upload.sh — POST results.json + error/visual screenshots to the PrestaFlow API.
# Mirrors src/upload/api.ts from PrestaFlow/github-action, plus a `ci` block so
# the backend's provider detector tags the run as gitlab_ci.
set -euo pipefail

API_URL="${PRESTAFLOW_API_URL:-https://api.prestaflow.io}"
TOKEN="${PRESTAFLOW_TOKEN:-}"
PROJECT_ID="${PRESTAFLOW_PROJECT_ID:-}"

if [ -z "$TOKEN" ]; then
  echo "upload: PRESTAFLOW_TOKEN is empty — refusing to call the API"
  exit 1
fi

# Same lookup order as the GitHub Action's findResultsJson().
RESULTS=""
for c in tests/prestaflow/results.json prestaflow/results.json; do
  if [ -f "$c" ]; then RESULTS="$c"; break; fi
done

if [ -z "$RESULTS" ]; then
  echo "upload: no results.json found (looked in tests/prestaflow/, prestaflow/) — skipping upload"
  exit 0
fi

echo "upload: sending $RESULTS to $API_URL/ci/github-action"

# GitLab-native `ci` block. DetectCIProvider on the backend reads these to tag
# the run as gitlab_ci.
CI_JSON=$(jq -n \
  --arg gitlab_ci        "true" \
  --arg pipeline_url     "${CI_PIPELINE_URL:-}" \
  --arg pipeline_id      "${CI_PIPELINE_ID:-}" \
  --arg user             "${GITLAB_USER_LOGIN:-}" \
  --arg commit_sha       "${CI_COMMIT_SHA:-}" \
  --arg ref_name         "${CI_COMMIT_REF_NAME:-}" \
  --arg project_path     "${CI_PROJECT_PATH:-}" \
  --arg mr_iid           "${CI_MERGE_REQUEST_IID:-}" \
  --arg mr_project_id    "${CI_MERGE_REQUEST_PROJECT_ID:-}" \
  '{GITLAB_CI: $gitlab_ci,
    CI_PIPELINE_URL: $pipeline_url,
    CI_PIPELINE_ID: $pipeline_id,
    GITLAB_USER_LOGIN: $user,
    CI_COMMIT_SHA: $commit_sha,
    CI_COMMIT_REF_NAME: $ref_name,
    CI_PROJECT_PATH: $project_path,
    CI_MERGE_REQUEST_IID: $mr_iid,
    CI_MERGE_REQUEST_PROJECT_ID: $mr_project_id}')

# Build the multipart form in an array so quoting stays sane. Provider-native
# GH-style field names are mirrored from the source action (branch, commit_sha,
# ref, ci_run_id, github_repository) so the existing backend controller doesn't
# have to special-case GitLab for those top-level fields.
FORM_ARGS=(
  -F "projectId=${PROJECT_ID}"
  -F "ci=${CI_JSON};type=application/json"
)
[ -n "${CI_COMMIT_REF_NAME:-}" ] && FORM_ARGS+=(-F "branch=${CI_COMMIT_REF_NAME}")
[ -n "${CI_COMMIT_SHA:-}" ]      && FORM_ARGS+=(-F "commit_sha=${CI_COMMIT_SHA}")
[ -n "${CI_COMMIT_REF_NAME:-}" ] && FORM_ARGS+=(-F "ref=refs/heads/${CI_COMMIT_REF_NAME}")
[ -n "${CI_PIPELINE_ID:-}" ]     && FORM_ARGS+=(-F "ci_run_id=${CI_PIPELINE_ID}")
[ -n "${CI_PROJECT_PATH:-}" ]    && FORM_ARGS+=(-F "github_repository=${CI_PROJECT_PATH}")

# results.json first, then error/visual screenshots. Upload-name rewriting
# matches src/upload/api.ts.
FORM_ARGS+=(-F "file[]=@${RESULTS};filename=results.json")

while IFS= read -r -d '' f; do
  FORM_ARGS+=(-F "file[]=@${f};filename=screens/$(basename "$f")")
done < <(find . -type f -path '*/prestaflow/screens/errors/*.png' -print0 2>/dev/null)

while IFS= read -r -d '' f; do
  FORM_ARGS+=(-F "file[]=@${f};filename=visual/actual/$(basename "$f")")
done < <(find . -type f -path '*/prestaflow/screens/actual/*.png' -print0 2>/dev/null)

while IFS= read -r -d '' f; do
  FORM_ARGS+=(-F "file[]=@${f};filename=visual/diff/$(basename "$f")")
done < <(find . -type f -path '*/prestaflow/screens/diff/*.png' -print0 2>/dev/null)

RESPONSE=$(curl -sS -X POST "${API_URL}/ci/github-action" \
  -H "X-Api-Token: ${TOKEN}" \
  "${FORM_ARGS[@]}" \
  --write-out '\n%{http_code}' || true)

HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
BODY=$(echo "$RESPONSE" | sed '$d')

if [ "$HTTP_CODE" -lt 200 ] || [ "$HTTP_CODE" -ge 300 ]; then
  echo "upload: API returned HTTP $HTTP_CODE"
  echo "$BODY" | head -c 2000
  # Mirror the GitHub Action's warn-and-continue behavior.
  exit 0
fi

REPORT_ID=$(echo "$BODY" | jq -r '.id // empty')
REPORT_URL=$(echo "$BODY" | jq -r '.url // empty')

echo "upload: report id=$REPORT_ID"
echo "upload: report url=$REPORT_URL"

# Persist for later scripts (comment-mr.sh, outputs.sh) via prestaflow.env,
# which becomes the job's dotenv report.
{
  echo "PRESTAFLOW_REPORT_ID=${REPORT_ID}"
  echo "PRESTAFLOW_REPORT_URL=${REPORT_URL}"
} >> prestaflow.env
