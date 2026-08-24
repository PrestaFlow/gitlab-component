#!/usr/bin/env bash
# visual-download.sh — Fetches the visual-regression baselines manifest and
# downloads each baseline PNG into visual-baseline/. Mirrors src/visual/prepare.ts,
# minus the @actions/cache layer (GitLab has no direct equivalent; consumers
# can wire cache: paths in their own job if they want the persistence).
set -euo pipefail

if [ "${PRESTAFLOW_VISUAL:-true}" != "true" ]; then
  echo "visual-download: visual disabled — skipping"
  exit 0
fi

API_URL="${PRESTAFLOW_API_URL:-https://api.prestaflow.io}"
TOKEN="${PRESTAFLOW_TOKEN:-}"
BRANCH="${CI_COMMIT_REF_NAME:-}"
BASELINE_DIR="${CI_PROJECT_DIR:-$PWD}/visual-baseline"

if [ -z "$TOKEN" ]; then
  echo "visual-download: PRESTAFLOW_TOKEN empty — skipping"
  exit 0
fi

URL="${API_URL}/ci/visual/baselines"
if [ -n "$BRANCH" ]; then
  # crude urlencode for common branch chars — good enough for slugs
  ENCODED=$(printf '%s' "$BRANCH" | jq -sRr @uri)
  URL="${URL}?branch=${ENCODED}"
fi

echo "visual-download: fetching manifest from $URL"

RESPONSE=$(curl -sS -X GET "$URL" \
  -H "X-Api-Token: ${TOKEN}" \
  --write-out '\n%{http_code}' || true)
HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
BODY=$(echo "$RESPONSE" | sed '$d')

if [ "$HTTP_CODE" = "404" ] || [ "$HTTP_CODE" = "501" ]; then
  echo "visual-download: API does not support visual baselines yet — skipping"
  exit 0
fi

if [ "$HTTP_CODE" -lt 200 ] || [ "$HTTP_CODE" -ge 300 ]; then
  echo "visual-download: manifest fetch failed (HTTP $HTTP_CODE), continuing without baselines"
  echo "$BODY" | head -c 1000
  exit 0
fi

COUNT=$(echo "$BODY" | jq -r '.baselines | length // 0')
if [ "$COUNT" = "0" ] || [ -z "$COUNT" ]; then
  echo "visual-download: no baselines in manifest — nothing to fetch"
  exit 0
fi

mkdir -p "$BASELINE_DIR"
echo "visual-download: downloading $COUNT baseline(s) into $BASELINE_DIR"

echo "$BODY" | jq -c '.baselines[]' | while IFS= read -r baseline; do
  NAME=$(echo "$baseline" | jq -r '.name')
  TAG=$(echo "$baseline" | jq -r '.tag')
  DL=$(echo "$baseline" | jq -r '.download_url')
  DEST="${BASELINE_DIR}/${NAME}--${TAG}.png"
  if ! curl -sS -f -o "$DEST" -H "X-Api-Token: ${TOKEN}" "${API_URL}${DL}"; then
    echo "visual-download: failed to fetch ${NAME}--${TAG}"
    rm -f "$DEST"
  fi
done

echo "visual-download: done ($(ls -1 "$BASELINE_DIR" 2>/dev/null | wc -l | tr -d ' ') file(s))"
