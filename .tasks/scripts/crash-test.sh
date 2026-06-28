#!/bin/bash
# Description: Deliberately crashes to test the error trap
set -euo pipefail
TASK=crash-test
PROJECT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
RESULTS="$PROJECT_DIR/.tasks/results.log"

trap '[[ ${EXIT_CODE:=$?} -ne 0 ]] && echo "$(date -Iseconds) [$TASK] ALERT: script crashed (exit $EXIT_CODE)" >> "$RESULTS"' EXIT

echo "About to crash..."
nonexistent_command_xyz
echo "This line should never run"
