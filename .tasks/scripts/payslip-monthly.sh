#!/bin/bash
# Description: Download monthly payslip from DATEV ANO and save to NAS. Runs 26th-31st.
set -euo pipefail
TASK=payslip-monthly
PROJECT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
PAYSLIP_DIR=/home/lalit/claudeclaw-cc/.payslip-automation
LOG_DIR="$PROJECT_DIR/.tasks/logs/$TASK"
RESULTS="$PROJECT_DIR/.tasks/results.log"
LOCK="/tmp/claudeclaw-$TASK.lock"

exec 9>"$LOCK"; flock -n 9 || exit 0

trap '[[ ${EXIT_CODE:=$?} -ne 0 ]] && echo "$(date -Iseconds) [$TASK] ALERT: script crashed (exit $EXIT_CODE)" >> "$RESULTS"' EXIT

mkdir -p "$LOG_DIR"
RUN_LOG="$LOG_DIR/$(date -Iseconds).log"
MONTH=$(date +%Y-%m)

{
  echo "ts:    $(date -Iseconds)"
  echo "month: $MONTH"
} > "$RUN_LOG"

# Try the fetch — exits 0=ok, 2=needs_login, 3=not_yet, 1=error
RESULT=$(cd "$PAYSLIP_DIR" && node monthly-fetch.mjs "$MONTH" 2>>"$RUN_LOG" || true)
STATUS_CODE=$(cd "$PAYSLIP_DIR" && node monthly-fetch.mjs "$MONTH" 2>>"$RUN_LOG"; echo $?) || true
FETCH_STATUS=$(echo "$RESULT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('status','error'))" 2>/dev/null || echo "error")

echo "fetch_status: $FETCH_STATUS" >> "$RUN_LOG"

case "$FETCH_STATUS" in
  ok)
    SAVED=$(echo "$RESULT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(', '.join(d.get('saved',[])))" 2>/dev/null || echo "unknown")
    echo "saved: $SAVED" >> "$RUN_LOG"
    echo "$(date -Iseconds) [$TASK] NOTIFY: payslip downloaded — $SAVED" >> "$RESULTS"
    ;;
  not_yet)
    echo "not available yet, will retry tomorrow" >> "$RUN_LOG"
    # Silent — cron fires again tomorrow
    ;;
  needs_login)
    echo "session expired — starting login flow" >> "$RUN_LOG"

    # Ask Lalit for his 2FA code
    CONTEXT='{"reason":"DATEV session expired — need 2FA to log in and download payslip","hint":"Open your authenticator app and enter the 6-digit code for DATEV-Konto"}'
    OTP=$("$PROJECT_DIR/bin/task-ask" "$TASK" "DATEV login needed for payslip download. Open authenticator app — what is your 6-digit DATEV-Konto code?" 1800 "$CONTEXT")

    if [ -z "$OTP" ]; then
      echo "$(date -Iseconds) [$TASK] ALERT: timed out waiting for DATEV 2FA code — payslip not downloaded" >> "$RESULTS"
      exit 0
    fi

    echo "got OTP, running login..." >> "$RUN_LOG"
    if node "$PAYSLIP_DIR/datev-login.mjs" "$OTP" >> "$RUN_LOG" 2>&1; then
      echo "login succeeded, retrying fetch..." >> "$RUN_LOG"
      RESULT2=$(cd "$PAYSLIP_DIR" && node monthly-fetch.mjs "$MONTH" 2>>"$RUN_LOG" || echo '{"status":"error"}')
      FETCH_STATUS2=$(echo "$RESULT2" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('status','error'))" 2>/dev/null || echo "error")
      if [ "$FETCH_STATUS2" = "ok" ]; then
        SAVED=$(echo "$RESULT2" | python3 -c "import sys,json; d=json.load(sys.stdin); print(', '.join(d.get('saved',[])))" 2>/dev/null || echo "unknown")
        echo "$(date -Iseconds) [$TASK] NOTIFY: payslip downloaded after login — $SAVED" >> "$RESULTS"
      else
        echo "$(date -Iseconds) [$TASK] ALERT: login succeeded but fetch failed (status=$FETCH_STATUS2)" >> "$RESULTS"
      fi
    else
      echo "$(date -Iseconds) [$TASK] ALERT: DATEV login failed — check the run log at $RUN_LOG" >> "$RESULTS"
    fi
    ;;
  *)
    echo "$(date -Iseconds) [$TASK] ALERT: payslip fetch error — $RESULT" >> "$RESULTS"
    ;;
esac

"$PROJECT_DIR/bin/task-cleanup-logs"
