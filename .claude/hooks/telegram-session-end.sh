#!/usr/bin/env bash
# telegram-session-end.sh — SessionEnd hook.
# Defensive cleanup when the Claude Code session terminates:
#   1. Force-flip in_telegram_turn=false in active.json (in case the Stop hook
#      missed the last turn — e.g. session killed mid-turn).
#   2. Delete a hanging tool-call progress message if one was left undeleted.
#   3. Reap bot.pid if its process is gone (orphan from a crashed bot run).
#
# Idempotent. Logs failures to stream.log, never blocks shutdown.

set -u
# Prefer the repo-local state dir when running inside a claudeclaw checkout
# (start.sh writes there). Fall back to the global ~/.claude/channels/telegram
# only when no repo-local dir exists.
if [ -n "${TELEGRAM_STATE_DIR:-}" ]; then
  TG_STATE_DIR="$TELEGRAM_STATE_DIR"
elif [ -n "${CLAUDE_PROJECT_DIR:-}" ] && [ -d "$CLAUDE_PROJECT_DIR/.telegram" ]; then
  TG_STATE_DIR="$CLAUDE_PROJECT_DIR/.telegram"
else
  TG_STATE_DIR="$HOME/.claude/channels/telegram"
fi
mkdir -p "$TG_STATE_DIR" 2>/dev/null || true
exec 2>>"$TG_STATE_DIR/stream.log"

STATE_FILE="$TG_STATE_DIR/active.json"
ENV_FILE="$TG_STATE_DIR/.env"
LOG_FILE="$TG_STATE_DIR/stream.log"
PID_FILE="$TG_STATE_DIR/bot.pid"

# --- 1+2. Clean up active.json + lingering progress message --------------
if [ -f "$STATE_FILE" ]; then
  IN_TURN=$(jq -r '.in_telegram_turn // false' "$STATE_FILE" 2>/dev/null)
  if [ "$IN_TURN" = "true" ]; then
    CHAT_ID=$(jq -r '.chat_id // empty' "$STATE_FILE")
    MSG_ID=$(jq -r '.progress_message_id // empty' "$STATE_FILE")
    if [ -n "$CHAT_ID" ] && [ -n "$MSG_ID" ]; then
      if [ -z "${TELEGRAM_BOT_TOKEN:-}" ] && [ -f "$ENV_FILE" ]; then
        # shellcheck disable=SC1090
        . "$ENV_FILE"
      fi
      if [ -n "${TELEGRAM_BOT_TOKEN:-}" ] && [ "$TELEGRAM_BOT_TOKEN" != "PASTE_YOUR_BOT_TOKEN_HERE" ]; then
        RESP=$(curl -s -X POST \
          -d "chat_id=${CHAT_ID}&message_id=${MSG_ID}" \
          "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/deleteMessage")
        OK=$(echo "$RESP" | jq -r '.ok // false' 2>/dev/null)
        if [ "$OK" != "true" ]; then
          echo "[$(date -Iseconds)] session-end deleteMessage failed (chat=$CHAT_ID msg=$MSG_ID): $RESP" >> "$LOG_FILE"
        fi
      fi
    fi
  fi
  TMP=$(mktemp)
  jq '.in_telegram_turn = false' "$STATE_FILE" > "$TMP" && mv "$TMP" "$STATE_FILE"
fi

# --- 3. Reap stale bot.pid -----------------------------------------------
if [ -f "$PID_FILE" ]; then
  PID=$(cat "$PID_FILE" 2>/dev/null)
  if [ -n "$PID" ] && ! kill -0 "$PID" 2>/dev/null; then
    rm -f "$PID_FILE"
    echo "[$(date -Iseconds)] session-end reaped stale bot.pid ($PID)" >> "$LOG_FILE"
  fi
fi

# --- Final vault digest pass ---
# Stop hook usually catches everything; this is the safety net for sessions
# that ended without a final Stop firing (manual exit, crash recovery).
HOOK_INPUT=$(cat 2>/dev/null || true)
export HOOK_INPUT
DIGEST_LIB="${CLAUDE_PROJECT_DIR:-$(pwd)}/.claude/hooks/lib/digest.sh"
if [ -f "$DIGEST_LIB" ]; then
  # shellcheck source=lib/digest.sh
  . "$DIGEST_LIB"
  digest_run "session-end" || true
fi

exit 0
