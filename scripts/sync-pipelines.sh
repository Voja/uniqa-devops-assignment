#!/usr/bin/env bash
# Mirror pipelines/*.yml (source of truth, mandated by the assignment) into .github/workflows/
# (the only folder GitHub Actions executes from).
#
#   scripts/sync-pipelines.sh          copy pipelines/*.yml -> .github/workflows/
#   scripts/sync-pipelines.sh --check  exit 1 if the two folders differ (used by CI)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="${ROOT}/pipelines"
DST="${ROOT}/.github/workflows"

if [[ "${1:-}" == "--check" ]]; then
  # README.md/.gitkeep live only in pipelines/; everything else must be byte-identical.
  if diff -r -q --exclude=README.md --exclude=.gitkeep "${SRC}" "${DST}"; then
    echo "OK: .github/workflows mirrors pipelines/"
  else
    echo "::error::.github/workflows is out of sync with pipelines/. Run scripts/sync-pipelines.sh" >&2
    exit 1
  fi
  exit 0
fi

mkdir -p "${DST}"
cp -v "${SRC}"/*.yml "${DST}/"
