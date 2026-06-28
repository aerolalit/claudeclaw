#!/bin/bash
# Demo task — proves the scheduled task system is operational.
# Full output goes to a per-run log. results.log only gets alerts.

TASK=demo
LOG_DIR=/home/lalit/claudeclaw/.tasks/logs/$TASK
RESULTS=/home/lalit/claudeclaw/.tasks/results.log

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

# Only surface to the session monitor on ALERT
if [ "$STATUS" = "ALERT" ]; then
  echo "$(date -Iseconds) [$TASK] ALERT: $DETAIL" >> "$RESULTS"
fi
