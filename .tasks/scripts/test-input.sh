#!/bin/bash
# Description: Tests the FIFO-based mid-run user input flow
set -euo pipefail
TASK=test-input
PROJECT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
LOG_DIR="$PROJECT_DIR/.tasks/logs/$TASK"
RESULTS="$PROJECT_DIR/.tasks/results.log"
LOCK="/tmp/claudeclaw-$TASK.lock"

exec 9>"$LOCK"; flock -n 9 || { echo "already running"; exit 0; }

trap '[[ ${EXIT_CODE:=$?} -ne 0 ]] && echo "$(date -Iseconds) [$TASK] ALERT: script crashed (exit $EXIT_CODE)" >> "$RESULTS"' EXIT

mkdir -p "$LOG_DIR"
RUN_LOG="$LOG_DIR/$(date -Iseconds).log"

{
  echo "ts:   $(date -Iseconds)"
  echo "task: $TASK"
  echo "step: asking user with structured context"
} > "$RUN_LOG"

CONTEXT='{"options":["red","blue","green"],"reason":"picking a theme colour"}'
ANSWER=$("$PROJECT_DIR/bin/task-ask" "$TASK" "Pick a colour for the theme" 300 "$CONTEXT")

{
  echo "answer: $ANSWER"
  echo "done:   $(date -Iseconds)"
} >> "$RUN_LOG"

if [ -z "$ANSWER" ]; then
  echo "$(date -Iseconds) [$TASK] ALERT: timed out waiting for colour input" >> "$RESULTS"
else
  echo "$(date -Iseconds) [$TASK] OK: theme colour set to '$ANSWER'" >> "$RESULTS"
fi

"$PROJECT_DIR/bin/task-cleanup-logs"
