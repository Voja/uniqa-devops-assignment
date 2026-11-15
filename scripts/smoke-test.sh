#!/usr/bin/env bash
# Post-deployment smoke test shared by cd-dev.yml and cd-prod.yml.
#
#   scripts/smoke-test.sh <base-url> <expected-env> <expected-version>
#
# Phase 1 "wait for rollout": poll GET /health (up to 30 x 10 s) until the NEW container answers,
#   i.e. HTTP 200 AND "version" == <expected-version> (the sha written to APP_VERSION) AND
#   "env" == <expected-env>. This avoids racing the asynchronous restart that follows
#   `az webapp config appsettings set` / `az webapp restart`.
# Phase 2 "functional": POST a transaction and GET /transactions, each retried up to 5 times
#   (5 s apart) on any non-2xx, because the platform may still be warming up.
# Every attempt is printed; any failure exits non-zero with a clear message.
set -euo pipefail

usage="usage: smoke-test.sh <base-url> <expected-env> <expected-version>"
BASE_URL="${1:?${usage}}"
EXPECTED_ENV="${2:?${usage}}"
EXPECTED_VERSION="${3:?${usage}}"
BASE_URL="${BASE_URL%/}" # tolerate a trailing slash in vars.APP_URL

# Overridable via environment (defaults: 30 x 10 s rollout wait, 5 x 5 s per request).
ROLLOUT_ATTEMPTS="${ROLLOUT_ATTEMPTS:-30}"
ROLLOUT_SLEEP="${ROLLOUT_SLEEP:-10}"
REQUEST_ATTEMPTS="${REQUEST_ATTEMPTS:-5}"
REQUEST_SLEEP="${REQUEST_SLEEP:-5}"

# http_call <method> <path> [json-body] -> sets globals HTTP_CODE and HTTP_BODY; never exits.
http_call() {
  local method="$1" path="$2" body="${3:-}" out
  if [[ -n "${body}" ]]; then
    out="$(curl -sS --max-time 30 -w '\n%{http_code}' -X "${method}" \
      -H 'Content-Type: application/json' -d "${body}" "${BASE_URL}${path}" 2>&1)" || true
  else
    out="$(curl -sS --max-time 30 -w '\n%{http_code}' -X "${method}" "${BASE_URL}${path}" 2>&1)" || true
  fi
  HTTP_CODE="${out##*$'\n'}"
  HTTP_BODY="${out%$'\n'*}"
  HTTP_BODY="${HTTP_BODY%$'\n'}" # Flask terminates JSON with a newline; keep log lines compact
  [[ "${HTTP_CODE}" =~ ^[0-9]{3}$ ]] || HTTP_CODE="000" # curl error (DNS, timeout, reset)
}

# json_field <key> <json> -> prints the string value of a top-level "key":"value" pair.
json_field() {
  sed -nE "s/.*\"$1\": ?\"([^\"]*)\".*/\1/p" <<<"$2"
}

fail() {
  echo "::error::$*" >&2
  exit 1
}

# ---------------------------------------------------------------------------
# Phase 1: wait until the new container (expected version + env) is serving.
# ---------------------------------------------------------------------------
echo "==> Phase 1: waiting for ${BASE_URL}/health to report version=${EXPECTED_VERSION} env=${EXPECTED_ENV}"
rolled_out=0
for attempt in $(seq 1 "${ROLLOUT_ATTEMPTS}"); do
  http_call GET /health
  version="$(json_field version "${HTTP_BODY}")"
  env_name="$(json_field env "${HTTP_BODY}")"
  echo "  [${attempt}/${ROLLOUT_ATTEMPTS}] HTTP ${HTTP_CODE} version=${version:-?} env=${env_name:-?} ${HTTP_BODY}"
  if [[ "${HTTP_CODE}" == "200" && "${version}" == "${EXPECTED_VERSION}" && "${env_name}" == "${EXPECTED_ENV}" ]]; then
    rolled_out=1
    break
  fi
  sleep "${ROLLOUT_SLEEP}"
done
if [[ "${rolled_out}" -ne 1 ]]; then
  fail "Rollout did not complete: /health never returned 200 with version=${EXPECTED_VERSION} and env=${EXPECTED_ENV} after $((ROLLOUT_ATTEMPTS * ROLLOUT_SLEEP)) s"
fi
echo "  rollout complete"

# ---------------------------------------------------------------------------
# Phase 2: functional checks with retries (platform may still be warming up).
# ---------------------------------------------------------------------------
# request_2xx <label> <method> <path> [json-body] -> retries until 2xx; HTTP_BODY holds the last body.
request_2xx() {
  local label="$1" method="$2" path="$3" body="${4:-}"
  echo "==> Phase 2: ${label}"
  for attempt in $(seq 1 "${REQUEST_ATTEMPTS}"); do
    http_call "${method}" "${path}" "${body}"
    echo "  [${attempt}/${REQUEST_ATTEMPTS}] HTTP ${HTTP_CODE} ${HTTP_BODY}"
    if [[ "${HTTP_CODE}" =~ ^2[0-9]{2}$ ]]; then
      return 0
    fi
    sleep "${REQUEST_SLEEP}"
  done
  fail "${label} failed: no 2xx response after ${REQUEST_ATTEMPTS} attempts (last HTTP ${HTTP_CODE})"
}

description="smoke-test ${EXPECTED_VERSION}"

request_2xx "POST /transactions" POST /transactions \
  "{\"amount\": 12.5, \"description\": \"${description}\"}"
[[ "${HTTP_CODE}" == "201" ]] || fail "POST /transactions returned HTTP ${HTTP_CODE}, expected 201"

request_2xx "GET /transactions" GET /transactions
grep -Fq "${description}" <<<"${HTTP_BODY}" \
  || fail "GET /transactions does not contain the record just created (\"${description}\")"

echo "Smoke test passed for ${BASE_URL} (env=${EXPECTED_ENV}, version=${EXPECTED_VERSION})"
