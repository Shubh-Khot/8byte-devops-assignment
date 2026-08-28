#!/usr/bin/env bash
#
# Post-deploy smoke test. Fails the pipeline if the freshly deployed service
# is not actually serving.
#
#   ./scripts/smoke-test.sh http://alb-dns-name [expected-build-sha]
#
# The build SHA check is the part that matters most. Without it a deploy that
# silently rolled back still "passes", because the old version answers /readyz
# perfectly well.

set -euo pipefail

BASE_URL="${1:?usage: smoke-test.sh <base-url> [expected-build]}"
EXPECTED_BUILD="${2:-}"
RETRIES="${RETRIES:-20}"
SLEEP="${SLEEP:-5}"

fail() { echo "FAIL: $*" >&2; exit 1; }
ok()   { echo "  ok: $*"; }

echo "Smoke testing ${BASE_URL}"

# ---------------------------------------------------------------------------
# 1. Wait for readiness.
#
# Retried rather than checked once: the ALB needs a moment to register the new
# targets even after ECS reports the service stable.
# ---------------------------------------------------------------------------
echo "[1/5] waiting for /readyz"
for attempt in $(seq 1 "$RETRIES"); do
  code=$(curl -fsS -o /tmp/readyz.json -w '%{http_code}' --max-time 10 "${BASE_URL}/readyz" 2>/dev/null || echo "000")
  if [ "$code" = "200" ]; then
    ok "ready after ${attempt} attempt(s)"
    break
  fi
  [ "$attempt" -eq "$RETRIES" ] && fail "/readyz never returned 200 (last: ${code})"
  echo "  attempt ${attempt}/${RETRIES}: ${code}, retrying in ${SLEEP}s"
  sleep "$SLEEP"
done

grep -q '"database":"ok"' /tmp/readyz.json || fail "readiness reports the database is unreachable"
ok "database reachable"

# ---------------------------------------------------------------------------
# 2. Confirm the running build is the one we just deployed.
# ---------------------------------------------------------------------------
echo "[2/5] verifying deployed build"
if [ -n "$EXPECTED_BUILD" ]; then
  live=$(curl -fsS --max-time 10 "${BASE_URL}/healthz" | sed -n 's/.*"build":"\([^"]*\)".*/\1/p')
  [ "$live" = "$EXPECTED_BUILD" ] || fail "expected build ${EXPECTED_BUILD}, service reports ${live} (rolled back?)"
  ok "running ${live}"
else
  echo "  skipped: no expected build passed"
fi

# ---------------------------------------------------------------------------
# 3. Exercise a real write path, not just a health endpoint. A service can
#    pass /readyz with a read-only or out-of-disk database.
# ---------------------------------------------------------------------------
echo "[3/5] create a task"
created=$(curl -fsS --max-time 10 -X POST "${BASE_URL}/tasks" \
  -H 'Content-Type: application/json' \
  -d "{\"title\":\"smoke-test $(date -u +%FT%TZ)\"}")
task_id=$(echo "$created" | sed -n 's/.*"id":\([0-9]*\).*/\1/p')
[ -n "$task_id" ] || fail "could not parse task id from: ${created}"
ok "created task ${task_id}"

echo "[4/5] read it back and clean up"
curl -fsS --max-time 10 "${BASE_URL}/tasks/${task_id}" >/dev/null || fail "created task is not readable"
curl -fsS --max-time 10 -X DELETE "${BASE_URL}/tasks/${task_id}" >/dev/null || fail "could not delete the test task"
ok "round-trip complete, test data removed"

# ---------------------------------------------------------------------------
# 5. Metrics endpoint, because the dashboards are useless without it.
# ---------------------------------------------------------------------------
echo "[5/5] metrics endpoint"
curl -fsS --max-time 10 "${BASE_URL}/metrics" | grep -q "http_requests_total" \
  || fail "/metrics is not exposing http_requests_total"
ok "metrics exposed"

echo "Smoke test passed."
