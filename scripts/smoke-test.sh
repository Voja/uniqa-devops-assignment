#!/usr/bin/env bash
# Post-deployment smoke test shared by cd-dev.yml and cd-prod.yml.
#
#   scripts/smoke-test.sh <base-url> <expected-env> [version-tag]
#
# 1. Polls GET /health (up to 12 x 10 s) until HTTP 200 and the JSON reports the expected env.
# 2. POSTs a transaction and expects HTTP 201.
# 3. GETs /transactions and expects the record just created to be listed.
# Any failure exits non-zero so the deployment job turns red.
set -euo pipefail

BASE_URL="${1:?usage: smoke-test.sh <base-url> <expected-env> [version-tag]}"
EXPECTED_ENV="${2:?usage: smoke-test.sh <base-url> <expected-env> [version-tag]}"
TAG="${3:-manual}"
BASE_URL="${BASE_URL%/}" # tolerate a trailing slash in vars.APP_URL

echo "==> 1/3 Waiting for ${BASE_URL}/health to report env=${EXPECTED_ENV}"
healthy=0
for attempt in $(seq 1 12); do
  body="$(curl -sS --max-time 15 -w '\n%{http_code}' "${BASE_URL}/health" || true)"
  code="${body##*$'\n'}"
  json="${body%$'\n'*}"
  echo "attempt ${attempt}/12 -> HTTP ${code:-000} ${json}"
  # Flask emits compact JSON; allow an optional space to be safe.
  if [[ "${code}" == "200" ]] && grep -Eq "\"env\": ?\"${EXPECTED_ENV}\"" <<<"${json}"; then
    healthy=1
    break
  fi
  sleep 10
done
if [[ "${healthy}" -ne 1 ]]; then
  echo "::error::/health never returned 200 with env=${EXPECTED_ENV}"
  exit 1
fi

echo "==> 2/3 POST /transactions"
desc="smoke-test ${TAG}"
resp="$(curl -sS --max-time 30 -w '\n%{http_code}' -X POST "${BASE_URL}/transactions" \
  -H 'Content-Type: application/json' \
  -d "{\"amount\": 12.5, \"description\": \"${desc}\"}")"
code="${resp##*$'\n'}"
echo "HTTP ${code} ${resp%$'\n'*}"
if [[ "${code}" != "201" ]]; then
  echo "::error::POST /transactions returned HTTP ${code}, expected 201"
  exit 1
fi

echo "==> 3/3 GET /transactions"
resp="$(curl -sS --max-time 30 -w '\n%{http_code}' "${BASE_URL}/transactions")"
code="${resp##*$'\n'}"
json="${resp%$'\n'*}"
echo "HTTP ${code} ${json}"
if [[ "${code}" != "200" ]] || ! grep -Fq "${desc}" <<<"${json}"; then
  echo "::error::GET /transactions did not return the record just created"
  exit 1
fi

echo "Smoke test passed for ${BASE_URL} (env=${EXPECTED_ENV})"
