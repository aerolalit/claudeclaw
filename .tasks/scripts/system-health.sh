#!/bin/bash
# Description: System health snapshot — CPU load, memory, disk. Sends NOTIFY every run.
set -euo pipefail
TASK=system-health
PROJECT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
LOG_DIR="$PROJECT_DIR/.tasks/logs/$TASK"
RESULTS="$PROJECT_DIR/.tasks/results.log"

trap '[[ ${EXIT_CODE:=$?} -ne 0 ]] && echo "$(date -Iseconds) [$TASK] ALERT: script crashed (exit $EXIT_CODE)" >> "$RESULTS"' EXIT

mkdir -p "$LOG_DIR"
RUN_LOG="$LOG_DIR/$(date -Iseconds).log"

CPU=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | tr -d ',')
MEM=$(free -m | awk '/^Mem:/{printf "%dMB used / %dMB total (%.0f%%)", $3, $2, $3/$2*100}')
DISK=$(df -h / | awk 'NR==2{printf "%s used / %s total (%s)", $3, $2, $5}')

{
  echo "ts:   $(date -Iseconds)"
  echo "cpu:  load=$CPU"
  echo "mem:  $MEM"
  echo "disk: $DISK"
} > "$RUN_LOG"

echo "$(date -Iseconds) [$TASK] NOTIFY: load=$CPU | mem=$MEM | disk=$DISK" >> "$RESULTS"

"$PROJECT_DIR/bin/task-cleanup-logs"
