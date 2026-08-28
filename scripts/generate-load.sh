#!/usr/bin/env bash
#
# Traffic generator for the local stack. Exists so the dashboards have
# something to show during a demo, and so the alert rules can be proven to
# fire rather than just being asserted to work.
#
#   ./scripts/generate-load.sh                  # 60s of normal traffic
#   ./scripts/generate-load.sh 120 errors       # 120s, with a burst of 500s
#
# `errors` mode hits /boom, which raises on purpose. That drives the 5xx ratio
# past 5% and trips HighErrorRate after its 5m `for:` window.

set -uo pipefail

BASE="${BASE_URL:-http://localhost:8000}"
DURATION="${1:-60}"
MODE="${2:-normal}"

echo "Generating ${MODE} traffic against ${BASE} for ${DURATION}s"
echo "Grafana: http://localhost:3000/d/task-api-service"

end=$(( $(date +%s) + DURATION ))
requests=0
errors=0

while [ "$(date +%s)" -lt "$end" ]; do
  # Ordinary read traffic - the bulk of any real workload.
  curl -fsS -o /dev/null "${BASE}/tasks" 2>/dev/null && requests=$((requests+1))

  # A write every few iterations, so the DB panels have something to show.
  if [ $((requests % 4)) -eq 0 ]; then
    id=$(curl -fsS -X POST "${BASE}/tasks" -H 'Content-Type: application/json' \
      -d "{\"title\":\"load ${requests}\"}" 2>/dev/null | sed -n 's/.*"id":\([0-9]*\).*/\1/p')
    [ -n "${id:-}" ] && curl -fsS -o /dev/null -X DELETE "${BASE}/tasks/${id}" 2>/dev/null
    requests=$((requests+2))
  fi

  # A 404, so the 4xx series is not flat and empty.
  if [ $((requests % 7)) -eq 0 ]; then
    curl -fsS -o /dev/null "${BASE}/tasks/999999" 2>/dev/null
    requests=$((requests+1))
  fi

  if [ "$MODE" = "errors" ] && [ $((requests % 5)) -eq 0 ]; then
    curl -fsS -o /dev/null "${BASE}/boom" 2>/dev/null
    errors=$((errors+1))
    requests=$((requests+1))
  fi

  sleep 0.2
done

echo "Done: ~${requests} requests, ${errors} deliberate errors."
