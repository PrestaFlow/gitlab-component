#!/usr/bin/env bash
# visual-upload.sh — No-op.
#
# The GitHub Action bundles the visual regression `actual/` and `diff/` PNGs
# into the same multipart POST as results.json (see src/upload/api.ts). This
# port keeps that shape, so upload.sh already ships the visual outputs — this
# file exists only to preserve the source Action's module-for-module structure
# and to leave an obvious hook if a separate endpoint is ever introduced.
set -euo pipefail

if [ "${PRESTAFLOW_VISUAL:-true}" != "true" ]; then
  exit 0
fi

echo "visual-upload: no-op — visual PNGs are shipped by upload.sh in the same multipart POST"
