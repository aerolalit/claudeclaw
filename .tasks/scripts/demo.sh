#!/bin/bash
# Description: Proves the scheduled task system is operational (demo only)
set -euo pipefail
TASK=demo
PROJECT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
LOG_DIR="$PROJECT_DIR/.tasks/logs/$TASK"
RESULTS="$PROJECT_DIR/.tasks/results.log"

trap '[[ ${EXIT_CODE:=$?} -ne 0 ]] && echo "$(date -Iseconds) [$TASK] ALERT: script crashed (exit $EXIT_CODE)" >> "$RESULTS"' EXIT

mkdir -p "$LOG_DIR"
RUN_LOG="$LOG_DIR/$(date -Iseconds).log"

STATUS=OK
DETAIL="scheduled task system is operational"

{
  echo "ts:     $(date -Iseconds)"
  echo "task:   $TASK"
  echo "status: $STATUS"
  echo "detail: $DETAIL"
} > "$RUN_LOG"

if [ "$STATUS" = "ALERT" ]; then
  echo "$(date -Iseconds) [$TASK] ALERT: $DETAIL" >> "$RESULTS"
fi

"$PROJECT_DIR/bin/task-cleanup-logs"
