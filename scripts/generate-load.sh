#!/usr/bin/env bash

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
  curl -fsS -o /dev/null "${BASE}/tasks" 2>/dev/null && requests=$((requests+1))

  if [ $((requests % 4)) -eq 0 ]; then
    id=$(curl -fsS -X POST "${BASE}/tasks" -H 'Content-Type: application/json' \
      -d "{\"title\":\"load ${requests}\"}" 2>/dev/null | sed -n 's/.*"id":\([0-9]*\).*/\1/p')
    [ -n "${id:-}" ] && curl -fsS -o /dev/null -X DELETE "${BASE}/tasks/${id}" 2>/dev/null
    requests=$((requests+2))
  fi

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
