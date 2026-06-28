#!/bin/bash
# Description: Alerts if any disk partition exceeds 85% usage, silent otherwise.
set -euo pipefail
TASK=disk-watch
PROJECT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
LOG_DIR="$PROJECT_DIR/.tasks/logs/$TASK"
RESULTS="$PROJECT_DIR/.tasks/results.log"
THRESHOLD=85

trap '[[ ${EXIT_CODE:=$?} -ne 0 ]] && echo "$(date -Iseconds) [$TASK] ALERT: script crashed (exit $EXIT_CODE)" >> "$RESULTS"' EXIT

mkdir -p "$LOG_DIR"
RUN_LOG="$LOG_DIR/$(date -Iseconds).log"

ALERTS=""
while IFS= read -r line; do
  pct=$(echo "$line" | awk '{print $5}' | tr -d '%')
  mount=$(echo "$line" | awk '{print $6}')
  used=$(echo "$line" | awk '{print $3}')
  total=$(echo "$line" | awk '{print $2}')
  echo "  $mount: ${pct}% ($used / $total)" >> "$RUN_LOG"
  if [ "$pct" -ge "$THRESHOLD" ]; then
    ALERTS="$ALERTS $mount=${pct}%"
  fi
done < <(df -h | awk 'NR>1 && $5 ~ /[0-9]+%/ {print}')

{
  echo "ts:        $(date -Iseconds)"
  echo "threshold: ${THRESHOLD}%"
  echo "partitions:"
} | cat - "$RUN_LOG" > /tmp/disk-watch-tmp && mv /tmp/disk-watch-tmp "$RUN_LOG"

if [ -n "$ALERTS" ]; then
  echo "$(date -Iseconds) [$TASK] ALERT: disk usage critical —$ALERTS" >> "$RESULTS"
fi

"$PROJECT_DIR/bin/task-cleanup-logs"
