#!/bin/bash
# Description: Asks what you want to focus on next, logs your answer. Tests INPUT_NEEDED flow.
set -euo pipefail
TASK=focus-check
PROJECT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
LOG_DIR="$PROJECT_DIR/.tasks/logs/$TASK"
RESULTS="$PROJECT_DIR/.tasks/results.log"
LOCK="/tmp/claudeclaw-$TASK.lock"

exec 9>"$LOCK"; flock -n 9 || exit 0

trap '[[ ${EXIT_CODE:=$?} -ne 0 ]] && echo "$(date -Iseconds) [$TASK] ALERT: script crashed (exit $EXIT_CODE)" >> "$RESULTS"' EXIT

mkdir -p "$LOG_DIR"
RUN_LOG="$LOG_DIR/$(date -Iseconds).log"

HOUR=$(date +%H)
CONTEXT=$(printf '{"hour":"%s","options":["deep work","emails/slack","meetings/reviews","break"]}' "$HOUR")

ANSWER=$("$PROJECT_DIR/bin/task-ask" "$TASK" "What are you focusing on next? (deep work / emails / meetings / break)" 1800 "$CONTEXT")

{
  echo "ts:     $(date -Iseconds)"
  echo "hour:   $HOUR"
  echo "focus:  ${ANSWER:-(no answer — timed out)}"
} > "$RUN_LOG"

if [ -z "$ANSWER" ]; then
  # timed out — silent, try again next interval
  exit 0
fi

echo "$(date -Iseconds) [$TASK] NOTIFY: focus logged — '$ANSWER'" >> "$RESULTS"

"$PROJECT_DIR/bin/task-cleanup-logs"
