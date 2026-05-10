#!/usr/bin/env bash
# telegram-stream.sh — PreToolUse + PostToolUse hook that streams tool calls
# to a single editable Telegram message. Reads state from ~/.claude/channels/
# telegram/active.json (set by the agent at start of a Telegram-originated turn).
#
# Bails silently if state file is missing, in_telegram_turn != true, or stale
# (last_edit_ts > 5min old). Designed to never block the agent: any failure
# logs to stream.log and exits 0.

set -u
# Prefer the repo-local state dir when this hook is running inside a
# claudeclaw checkout (start.sh writes there). Fall back to the global
# ~/.claude/channels/telegram only when no repo-local dir exists.
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
DEBOUNCE_MS=1200       # min ms between Telegram API calls
STALE_SEC=300          # state file expires after this many seconds idle
MAX_BUFFER_CHARS=3500  # leave room under Telegram's 4096 cap

# --- Read stdin ---
INPUT=$(cat)
if [ -z "$INPUT" ]; then exit 0; fi

# --- Bail if state file missing or turn not active ---
if [ ! -f "$STATE_FILE" ]; then exit 0; fi
IN_TURN=$(jq -r '.in_telegram_turn // false' "$STATE_FILE" 2>/dev/null)
if [ "$IN_TURN" != "true" ]; then exit 0; fi

# --- Bail if state file stale ---
NOW_MS=$(($(date +%s%N 2>/dev/null || echo $(($(date +%s) * 1000000000))) / 1000000))
LAST_TS=$(jq -r '.last_edit_ts // 0' "$STATE_FILE" 2>/dev/null)
AGE_SEC=$(( (NOW_MS - LAST_TS) / 1000 ))
if [ "$AGE_SEC" -gt "$STALE_SEC" ]; then exit 0; fi

# --- Load token (env wins; .env file is a fallback) ---
if [ -z "${TELEGRAM_BOT_TOKEN:-}" ] && [ -f "$ENV_FILE" ]; then
  # shellcheck disable=SC1090
  . "$ENV_FILE"
fi
if [ -z "${TELEGRAM_BOT_TOKEN:-}" ] || [ "$TELEGRAM_BOT_TOKEN" = "PASTE_YOUR_BOT_TOKEN_HERE" ]; then
  exit 0
fi

# --- Parse hook input ---
EVENT=$(echo "$INPUT" | jq -r '.hook_event_name // empty')
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty')
[ -z "$EVENT" ] || [ -z "$TOOL" ] && exit 0

# Skip the heartbeat sub-agent's own tool calls — they happen in the main
# session context. We detect by the Agent description matching "Heartbeat".
if [ "$TOOL" = "Agent" ]; then
  AGENT_DESC=$(echo "$INPUT" | jq -r '.tool_input.description // empty')
  case "$AGENT_DESC" in
    *Heartbeat*|*heartbeat*) exit 0 ;;
  esac
fi

# Skip Telegram MCP tool calls — replying to ourselves is noise.
case "$TOOL" in
  mcp__plugin_telegram_telegram__*) exit 0 ;;
esac

# Skip the heartbeat-arming chain on session start. The agent runs:
#   Skill(loop) → ToolSearch(CronCreate) → CronCreate → ...
# That's plumbing for arming the recurring heartbeat — not user-facing work.
# Filter the noise out of the Telegram tool-call stream.
if [ "$TOOL" = "Skill" ]; then
  SKILL_NAME=$(echo "$INPUT" | jq -r '.tool_input.skill // empty')
  [ "$SKILL_NAME" = "loop" ] && exit 0
fi
case "$TOOL" in
  CronCreate|CronList|CronDelete|ToolSearch) exit 0 ;;
esac

# --- Per-tool emoji + brief input formatter ---
emoji_for() {
  case "$1" in
    Read) echo "📖" ;;
    Edit|Write|MultiEdit) echo "✏️" ;;
    Bash) echo "⚡" ;;
    Grep) echo "🔍" ;;
    Glob) echo "🗂️" ;;
    Agent|Task) echo "🤖" ;;
    WebFetch|WebSearch) echo "🌐" ;;
    TodoWrite) echo "📝" ;;
    mcp__*) echo "🛠️" ;;
    *) echo "🔧" ;;
  esac
}

format_input() {
  local tool="$1"
  local input_json="$2"
  local desc=""
  case "$tool" in
    Read|Edit|Write|MultiEdit)
      desc=$(echo "$input_json" | jq -r '.file_path // empty' 2>/dev/null)
      ;;
    Bash)
      desc=$(echo "$input_json" | jq -r '.command // empty' 2>/dev/null | head -1)
      ;;
    Grep)
      local pattern path
      pattern=$(echo "$input_json" | jq -r '.pattern // empty' 2>/dev/null)
      path=$(echo "$input_json" | jq -r '.path // ""' 2>/dev/null)
      desc="$pattern${path:+ in $path}"
      ;;
    Glob)
      desc=$(echo "$input_json" | jq -r '.pattern // empty' 2>/dev/null)
      ;;
    Agent|Task)
      local subtype d
      subtype=$(echo "$input_json" | jq -r '.subagent_type // ""' 2>/dev/null)
      d=$(echo "$input_json" | jq -r '.description // empty' 2>/dev/null)
      desc="${subtype:+$subtype: }$d"
      ;;
    WebFetch)
      desc=$(echo "$input_json" | jq -r '.url // empty' 2>/dev/null)
      ;;
    WebSearch)
      desc=$(echo "$input_json" | jq -r '.query // empty' 2>/dev/null)
      ;;
    TodoWrite)
      local n
      n=$(echo "$input_json" | jq -r '.todos | length' 2>/dev/null)
      desc="$n todos"
      ;;
    *)
      desc=$(echo "$input_json" | jq -c . 2>/dev/null | head -c 80)
      ;;
  esac
  echo "$desc" | head -c 80
}

format_output() {
  local tool="$1"
  local response_json="$2"
  case "$tool" in
    Read)
      local lines
      lines=$(echo "$response_json" | jq -r '.file.numLines // empty' 2>/dev/null)
      [ -n "$lines" ] && echo "$lines lines" && return
      echo "$response_json" | jq -r 'if type=="string" then (split("\n") | length | tostring + " lines") else "ok" end' 2>/dev/null
      ;;
    Edit|Write|MultiEdit)
      echo "ok"
      ;;
    Bash)
      local stdout stderr
      stdout=$(echo "$response_json" | jq -r '.stdout // empty' 2>/dev/null)
      stderr=$(echo "$response_json" | jq -r '.stderr // empty' 2>/dev/null)
      local out="${stdout}${stderr}"
      [ -z "$out" ] && out="ok"
      echo "$out" | tr '\n' ' ' | tail -c 100
      ;;
    Grep|Glob)
      local n
      n=$(echo "$response_json" | jq -r 'if type=="array" then (length|tostring + " matches") elif .filenames then (.filenames|length|tostring + " matches") else "ok" end' 2>/dev/null)
      echo "${n:-ok}"
      ;;
    Agent|Task)
      local s
      s=$(echo "$response_json" | jq -r 'if type=="string" then . elif .content then .content else (.|tostring) end' 2>/dev/null | head -c 80)
      echo "${s:-ok}"
      ;;
    *)
      echo "$response_json" | jq -c . 2>/dev/null | head -c 80
      ;;
  esac
}

html_escape() {
  printf '%s' "$1" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g'
}

EMOJI=$(emoji_for "$TOOL")
INPUT_DESC=$(format_input "$TOOL" "$(echo "$INPUT" | jq -c '.tool_input // {}')")
INPUT_DESC_ESC=$(html_escape "$INPUT_DESC")

# --- Read current buffer + chat info ---
CHAT_ID=$(jq -r '.chat_id // empty' "$STATE_FILE")
MSG_ID=$(jq -r '.progress_message_id // empty' "$STATE_FILE")
BUFFER=$(jq -r '.buffer // ""' "$STATE_FILE")
[ -z "$CHAT_ID" ] && exit 0
# MSG_ID may be empty on first qualifying tool call — we lazy-create below.

# --- Per-chat streaming toggle (via /stream off in Telegram). Default: enabled. ---
# Note: use raw .enabled rather than `.enabled // true` — jq's // treats false
# as falsy and returns the right-hand side, so `false // true` evaluates to true.
STREAM_SETTINGS_FILE="$TG_STATE_DIR/stream_settings.json"
if [ -f "$STREAM_SETTINGS_FILE" ]; then
  RAW_ENABLED=$(jq -r --arg cid "$CHAT_ID" '.[$cid].enabled' "$STREAM_SETTINGS_FILE" 2>/dev/null)
  if [ "$RAW_ENABLED" = "false" ]; then exit 0; fi
fi

# --- Build the new line based on event ---
if [ "$EVENT" = "PreToolUse" ]; then
  NEW_LINE="🔄 ${EMOJI} ${TOOL}(<code>${INPUT_DESC_ESC}</code>)"
  # Append to buffer
  if [ -n "$BUFFER" ]; then
    NEW_BUFFER="${BUFFER}
${NEW_LINE}"
  else
    NEW_BUFFER="$NEW_LINE"
  fi
elif [ "$EVENT" = "PostToolUse" ]; then
  RESPONSE_JSON=$(echo "$INPUT" | jq -c '.tool_response // {}')
  OUT_DESC=$(format_output "$TOOL" "$RESPONSE_JSON")
  OUT_DESC_ESC=$(html_escape "$OUT_DESC")
  NEW_LINE="✅ ${EMOJI} ${TOOL}(<code>${INPUT_DESC_ESC}</code>) → <code>${OUT_DESC_ESC}</code>"
  # Replace last line (which should be the matching PreToolUse line)
  NEW_BUFFER=$(echo "$BUFFER" | sed '$d')
  if [ -n "$NEW_BUFFER" ]; then
    NEW_BUFFER="${NEW_BUFFER}
${NEW_LINE}"
  else
    NEW_BUFFER="$NEW_LINE"
  fi
else
  exit 0
fi

# --- Truncate buffer if over limit ---
BUF_LEN=${#NEW_BUFFER}
if [ "$BUF_LEN" -gt "$MAX_BUFFER_CHARS" ]; then
  # Drop oldest lines until under limit, prepend ellipsis
  # Simple strategy: keep the last ~80% of lines
  LINE_COUNT=$(echo "$NEW_BUFFER" | wc -l | tr -d ' ')
  KEEP=$(( LINE_COUNT * 8 / 10 ))
  ELIDED=$(( LINE_COUNT - KEEP ))
  TAIL=$(echo "$NEW_BUFFER" | tail -n "$KEEP")
  NEW_BUFFER="... (${ELIDED} earlier steps elided) ...
${TAIL}"
fi

# --- Debounce: skip Telegram call if too soon, but still update state ---
SHOULD_SEND=true
if [ "$AGE_SEC" -lt 2 ]; then
  AGE_MS=$(( NOW_MS - LAST_TS ))
  if [ "$AGE_MS" -lt "$DEBOUNCE_MS" ]; then
    SHOULD_SEND=false
  fi
fi

# --- Update state file (atomic via mv) ---
TMP_STATE=$(mktemp)
jq --arg b "$NEW_BUFFER" --argjson ts "$NOW_MS" \
   '.buffer = $b | .last_edit_ts = $ts' "$STATE_FILE" > "$TMP_STATE" && mv "$TMP_STATE" "$STATE_FILE"

# --- Fire typing indicator (fire-and-forget, ~5s lifespan) ---
curl -s -X POST \
  -d "chat_id=${CHAT_ID}&action=typing" \
  "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendChatAction" >/dev/null 2>&1 &

# --- Send (first call) or Edit (subsequent) ---
if [ "$SHOULD_SEND" = "true" ]; then
  if [ -z "$MSG_ID" ]; then
    # First qualifying tool call this turn — send a fresh message and capture id.
    RESP=$(curl -s -X POST \
      -H "Content-Type: application/json" \
      -d "$(jq -n --arg cid "$CHAT_ID" --arg txt "$NEW_BUFFER" \
            '{chat_id: $cid, text: $txt, parse_mode: "HTML"}')" \
      "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage")
    OK=$(echo "$RESP" | jq -r '.ok // false' 2>/dev/null)
    if [ "$OK" = "true" ]; then
      NEW_MSG_ID=$(echo "$RESP" | jq -r '.result.message_id // empty')
      if [ -n "$NEW_MSG_ID" ]; then
        TMP_STATE=$(mktemp)
        jq --arg mid "$NEW_MSG_ID" '.progress_message_id = $mid' \
          "$STATE_FILE" > "$TMP_STATE" && mv "$TMP_STATE" "$STATE_FILE"
      fi
    else
      echo "[$(date -Iseconds)] $EVENT $TOOL sendMessage failed: $RESP" >> "$LOG_FILE"
    fi
  else
    # Subsequent tool calls — edit the existing progress message.
    RESP=$(curl -s -X POST \
      -H "Content-Type: application/json" \
      -d "$(jq -n --arg cid "$CHAT_ID" --arg mid "$MSG_ID" --arg txt "$NEW_BUFFER" \
            '{chat_id: $cid, message_id: ($mid|tonumber), text: $txt, parse_mode: "HTML"}')" \
      "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/editMessageText")
    OK=$(echo "$RESP" | jq -r '.ok // false' 2>/dev/null)
    if [ "$OK" != "true" ]; then
      RETRY_AFTER=$(echo "$RESP" | jq -r '.parameters.retry_after // 0' 2>/dev/null)
      if [ "$RETRY_AFTER" -gt 0 ] && [ "$RETRY_AFTER" -le 10 ]; then
        sleep "$RETRY_AFTER"
        curl -s -X POST \
          -H "Content-Type: application/json" \
          -d "$(jq -n --arg cid "$CHAT_ID" --arg mid "$MSG_ID" --arg txt "$NEW_BUFFER" \
                '{chat_id: $cid, message_id: ($mid|tonumber), text: $txt, parse_mode: "HTML"}')" \
          "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/editMessageText" >/dev/null 2>&1 || true
      else
        echo "[$(date -Iseconds)] $EVENT $TOOL: $RESP" >> "$LOG_FILE"
      fi
    fi
  fi
fi

exit 0
