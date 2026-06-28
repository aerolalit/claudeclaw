#!/bin/bash
# Description: Proves the scheduled task system is operational (demo only)
TASK=demo
PROJECT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
LOG_DIR="$PROJECT_DIR/.tasks/logs/$TASK"
RESULTS="$PROJECT_DIR/.tasks/results.log"

mkdir -p "$LOG_DIR"
RUN_LOG="$LOG_DIR/$(date -Iseconds).log"

trap 'echo "$(date -Iseconds) [$TASK] ALERT: script crashed (exit $?)" >> "$RESULTS"' ERR

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
