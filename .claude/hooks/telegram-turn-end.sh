#!/usr/bin/env bash
# telegram-turn-end.sh — Stop hook.
# At end of turn: delete the streamed tool-call progress message (if one was
# created this turn) so the chat is left with just the inbound + final reply.
# Then flip in_telegram_turn=false so straggler hooks bail.

set -u
TG_STATE_DIR="${TELEGRAM_STATE_DIR:-$HOME/.claude/channels/telegram}"
mkdir -p "$TG_STATE_DIR" 2>/dev/null || true
exec 2>>"$TG_STATE_DIR/stream.log"

STATE_FILE="$TG_STATE_DIR/active.json"
ENV_FILE="$TG_STATE_DIR/.env"
LOG_FILE="$TG_STATE_DIR/stream.log"

[ ! -f "$STATE_FILE" ] && exit 0

IN_TURN=$(jq -r '.in_telegram_turn // false' "$STATE_FILE" 2>/dev/null)
[ "$IN_TURN" != "true" ] && exit 0

CHAT_ID=$(jq -r '.chat_id // empty' "$STATE_FILE")
MSG_ID=$(jq -r '.progress_message_id // empty' "$STATE_FILE")

# Delete the tool-call stream message if one was created.
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
      echo "[$(date -Iseconds)] turn-end deleteMessage failed (chat=$CHAT_ID msg=$MSG_ID): $RESP" >> "$LOG_FILE"
    fi
  fi
fi

TMP=$(mktemp)
jq '.in_telegram_turn = false' "$STATE_FILE" > "$TMP" && mv "$TMP" "$STATE_FILE"

exit 0
