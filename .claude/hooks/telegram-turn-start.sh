#!/usr/bin/env bash
# telegram-turn-start.sh — UserPromptSubmit hook.
# On a Telegram-routed prompt: react 👀 to the inbound message and write
# active.json with chat_id + in_telegram_turn=true. No placeholder is sent;
# the streaming hook lazily creates the progress message on the first
# non-telegram tool call. Trivial answers (no tools) leave the chat clean.
#
# Bails silently for non-Telegram prompts. Any failure logs to stream.log
# and exits 0 — never blocks the agent.

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
LAST_CHAT_FILE="$TG_STATE_DIR/last_chat.txt"
ENV_FILE="$TG_STATE_DIR/.env"
LOG_FILE="$TG_STATE_DIR/stream.log"

INPUT=$(cat)
[ -z "$INPUT" ] && exit 0

# Pull the user prompt out of the hook payload.
PROMPT=$(echo "$INPUT" | jq -r '.prompt // empty' 2>/dev/null)
[ -z "$PROMPT" ] && exit 0

# Only act on Telegram-routed prompts. Runtime emits
# source="plugin:telegram:telegram" (plugin docs claim "telegram" — stale).
case "$PROMPT" in
  *'<channel source="'*'telegram'*'"'*) ;;
  *) exit 0 ;;
esac

# Extract chat_id and inbound message_id from the channel tag.
CHAT_ID=$(echo "$PROMPT" | grep -oE 'chat_id="[^"]+"' | head -1 | sed 's/chat_id="\([^"]*\)"/\1/')
INBOUND_MSG_ID=$(echo "$PROMPT" | grep -oE 'message_id="[^"]+"' | head -1 | sed 's/message_id="\([^"]*\)"/\1/')
[ -z "$CHAT_ID" ] && exit 0

# Load bot token. Process env wins; .env file is a fallback.
if [ -z "${TELEGRAM_BOT_TOKEN:-}" ] && [ -f "$ENV_FILE" ]; then
  # shellcheck disable=SC1090
  . "$ENV_FILE"
fi
if [ -z "${TELEGRAM_BOT_TOKEN:-}" ] || [ "$TELEGRAM_BOT_TOKEN" = "PASTE_YOUR_BOT_TOKEN_HERE" ]; then
  exit 0
fi

# React 👀 to the inbound message — instant "I see you" signal.
if [ -n "$INBOUND_MSG_ID" ]; then
  curl -s -X POST \
    -H "Content-Type: application/json" \
    -d "$(jq -n --arg cid "$CHAT_ID" --arg mid "$INBOUND_MSG_ID" \
          '{chat_id: $cid, message_id: ($mid|tonumber), reaction: [{type: "emoji", emoji: "👀"}]}')" \
    "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/setMessageReaction" >/dev/null 2>&1 &
fi

# Write state — no progress_message_id yet; streaming hook creates it lazily.
NOW_MS=$(($(date +%s%N 2>/dev/null || echo $(($(date +%s) * 1000000000))) / 1000000))
TMP=$(mktemp)
jq -n --arg cid "$CHAT_ID" --argjson ts "$NOW_MS" \
  '{chat_id: $cid, progress_message_id: "", in_telegram_turn: true, buffer: "", last_edit_ts: $ts}' \
  > "$TMP" && mv "$TMP" "$STATE_FILE"

# Cache chat_id for heartbeat alerts.
echo "$CHAT_ID" > "$LAST_CHAT_FILE"

# Fire typing indicator (fire-and-forget).
curl -s -X POST \
  -d "chat_id=${CHAT_ID}&action=typing" \
  "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendChatAction" >/dev/null 2>&1 &

exit 0
