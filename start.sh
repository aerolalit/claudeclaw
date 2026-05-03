#!/usr/bin/env bash
# start.sh — bootstrap and launch the Telegram-channel session.
#
# Usage:
#   ./start.sh              # interactive, Telegram + bypass permissions
#   ./start.sh --no-tg      # plain interactive, no channel
#
# First run does:
#   1. Install plugin npm deps.
#   2. Register the local "claudeclaw" plugin marketplace.
#   3. Install the telegram plugin from that marketplace.
#   4. Prompt for TELEGRAM_BOT_TOKEN if not set; save to .env (gitignored).
#   5. If no Telegram allowlist entries exist, run the pairing flow:
#      start the bot standalone, prompt the user to DM it, capture the
#      6-char pairing code from stdin, write the senderId to allowFrom.
#
# Subsequent runs detect prior setup and skip these steps.
#
# To pick up local edits to plugins/telegram/server.ts, run inside Claude:
#   /plugin marketplace update claudeclaw
#   /plugin uninstall telegram@claudeclaw
#   /plugin install telegram@claudeclaw

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_DIR="$REPO_ROOT/plugins/telegram"
MARKETPLACE_NAME="claudeclaw"
PLUGIN_REF="telegram@${MARKETPLACE_NAME}"
ENV_FILE="$REPO_ROOT/.env"
# All Telegram state (access.json, .env, bot.pid, inbox/) lives inside the
# repo so this workspace owns its own bot and pairing — nothing in $HOME.
# Picked up by the plugin via TELEGRAM_STATE_DIR (see server.ts).
STATE_DIR="$REPO_ROOT/.telegram"
ACCESS_FILE="$STATE_DIR/access.json"
PAIRING_TIMEOUT=180  # seconds to wait for user to DM the bot

mkdir -p "$STATE_DIR"
chmod 700 "$STATE_DIR" 2>/dev/null || true

# --- Load repo-local .env if present ---
if [ -f "$ENV_FILE" ]; then
  set -a
  # shellcheck disable=SC1091
  . "$ENV_FILE"
  set +a
fi

# --- Tell the plugin (and standalone bot below) where to put state ---
export TELEGRAM_STATE_DIR="$STATE_DIR"

# --- Ensure Claude Code is installed and on PATH ---
if ! command -v claude >/dev/null 2>&1; then
  echo "Claude Code ('claude') not found on PATH."
  echo "  This script can install it from https://claude.ai/install.sh"
  read -r -p "Install now? [Y/n] " reply
  case "${reply:-Y}" in
    [Nn]*)
      echo "Aborting. Install manually: curl -fsSL https://claude.ai/install.sh | bash"
      exit 1
      ;;
  esac
  curl -fsSL https://claude.ai/install.sh | bash || {
    echo "ERROR: install failed." >&2
    echo "  Try manually: curl -fsSL https://claude.ai/install.sh | bash" >&2
    exit 1
  }
  # Pick up the freshly installed binary in this script's PATH.
  for p in "$HOME/.local/bin" "$HOME/bin" "/usr/local/bin"; do
    [ -x "$p/claude" ] && export PATH="$p:$PATH" && break
  done
  if ! command -v claude >/dev/null 2>&1; then
    echo "ERROR: claude installed but not found on PATH." >&2
    echo "  Open a new shell (so .bashrc loads) and re-run ./start.sh" >&2
    exit 1
  fi
  echo
  echo "Claude Code installed. Now authenticate (see instructions below)."
fi

# --- Ensure Claude Code is authenticated ---
# Three valid auth states:
#   1. CLAUDE_CODE_OAUTH_TOKEN env var (headless setup-token flow).
#   2. ~/.claude/.credentials.json exists AND ~/.claude.json marks onboarding done.
# Note: presence of `oauthAccount` in .claude.json is NOT sufficient — that's
# just profile metadata; the actual token lives in .credentials.json, and
# interactive `claude` blocks on the onboarding wizard if hasCompletedOnboarding
# is not true.
authed=false
if [ -n "${CLAUDE_CODE_OAUTH_TOKEN:-}" ]; then
  authed=true
elif [ -s "$HOME/.claude/.credentials.json" ] && \
     [ -f "$HOME/.claude.json" ] && \
     grep -q '"hasCompletedOnboarding"[[:space:]]*:[[:space:]]*true' "$HOME/.claude.json" 2>/dev/null; then
  authed=true
fi

if [ "$authed" != "true" ]; then
  cat <<'EOF'

Claude Code is installed but not authenticated.
Pick how you want to authenticate:

  [1] Headless (paste a setup-token) — for servers, Pi, VPS, no browser here
  [2] Desktop  (run `claude login`)  — for Mac, desktop Linux with a browser
  [3] Quit

EOF
  read -r -p "Choice [1/2/3]: " auth_choice
  case "${auth_choice:-1}" in
    1)
      cat <<'EOF'

On a different machine WITH a browser, run:

    claude setup-token

Sign in to claude.ai when prompted. Copy the long token it prints.
(Requires a Claude Pro / Max / Team subscription. Token valid ~1 year.)

EOF
      read -r -p "Paste the setup-token here: " setup_token
      setup_token="$(echo "$setup_token" | tr -d '[:space:]')"
      if [ -z "$setup_token" ]; then
        echo "ERROR: no token provided" >&2
        exit 1
      fi
      # Write to .env (replace existing line if present, else append).
      touch "$ENV_FILE"
      if grep -q "^CLAUDE_CODE_OAUTH_TOKEN=" "$ENV_FILE" 2>/dev/null; then
        sed -i.bak "s|^CLAUDE_CODE_OAUTH_TOKEN=.*|CLAUDE_CODE_OAUTH_TOKEN=${setup_token}|" "$ENV_FILE" && rm -f "$ENV_FILE.bak"
      else
        echo "CLAUDE_CODE_OAUTH_TOKEN=${setup_token}" >> "$ENV_FILE"
      fi
      chmod 600 "$ENV_FILE"
      export CLAUDE_CODE_OAUTH_TOKEN="$setup_token"
      # Mark onboarding done so interactive `claude` doesn't block on the wizard.
      mkdir -p "$HOME/.claude"
      if [ ! -f "$HOME/.claude.json" ]; then
        echo '{"hasCompletedOnboarding":true}' > "$HOME/.claude.json"
      elif ! grep -q '"hasCompletedOnboarding"[[:space:]]*:[[:space:]]*true' "$HOME/.claude.json"; then
        # File exists but missing the flag — patch it. Best effort with jq, fall back to overwrite.
        if command -v jq >/dev/null 2>&1; then
          tmp=$(mktemp); jq '.hasCompletedOnboarding=true' "$HOME/.claude.json" > "$tmp" && mv "$tmp" "$HOME/.claude.json"
        else
          echo '{"hasCompletedOnboarding":true}' > "$HOME/.claude.json"
        fi
      fi
      chmod 600 "$HOME/.claude.json"
      echo
      echo "✔ Token saved to .env and onboarding marked complete."
      ;;
    2)
      echo
      echo "Run:  claude login"
      echo "Then re-run ./start.sh"
      exit 0
      ;;
    *)
      echo "Aborting."
      exit 1
      ;;
  esac
fi

# --- Ensure plugin dependencies are installed ---
if [ ! -d "$PLUGIN_DIR/node_modules" ]; then
  echo "First run — installing telegram plugin dependencies..."
  if ! command -v npm >/dev/null 2>&1; then
    echo "ERROR: npm not found. Install Node.js (>=18): https://nodejs.org" >&2
    exit 1
  fi
  (cd "$PLUGIN_DIR" && npm install --silent) || {
    echo "ERROR: npm install failed in $PLUGIN_DIR" >&2
    exit 1
  }
fi

# --- Register marketplace if not already added ---
if ! claude plugin marketplace list 2>/dev/null | grep -qE "^[[:space:]]*[❯>][[:space:]]+${MARKETPLACE_NAME}[[:space:]]*$"; then
  echo "Registering claudeclaw plugin marketplace from $REPO_ROOT..."
  claude plugin marketplace add "$REPO_ROOT" || {
    echo "ERROR: failed to add marketplace at $REPO_ROOT" >&2
    exit 1
  }
fi

# --- Install plugin if not already installed ---
if ! claude plugin list 2>/dev/null | grep -qE "^[[:space:]]*[❯>][[:space:]]+${PLUGIN_REF}([[:space:]]|$)"; then
  echo "Installing $PLUGIN_REF (project scope)..."
  echo "y" | claude plugin install "$PLUGIN_REF" --scope project || {
    echo "ERROR: failed to install $PLUGIN_REF" >&2
    exit 1
  }
fi

# --- Skip Telegram setup if --no-tg ---
if [ "${1:-}" = "--no-tg" ]; then
  cd "$REPO_ROOT" && exec claude
fi

# --- Prompt for bot token if missing ---
if [ -z "${TELEGRAM_BOT_TOKEN:-}" ]; then
  echo
  echo "Telegram bot token not configured."
  echo "  Get one from @BotFather on Telegram (/newbot)."
  echo
  read -r -p "Paste your bot token: " TELEGRAM_BOT_TOKEN
  if [ -z "$TELEGRAM_BOT_TOKEN" ]; then
    echo "ERROR: no token provided" >&2
    exit 1
  fi
  # Persist to repo .env (creates or appends).
  if [ -f "$ENV_FILE" ] && grep -q "^TELEGRAM_BOT_TOKEN=" "$ENV_FILE"; then
    # Replace existing line.
    sed -i.bak "s|^TELEGRAM_BOT_TOKEN=.*|TELEGRAM_BOT_TOKEN=${TELEGRAM_BOT_TOKEN}|" "$ENV_FILE" && rm -f "$ENV_FILE.bak"
  else
    echo "TELEGRAM_BOT_TOKEN=${TELEGRAM_BOT_TOKEN}" >> "$ENV_FILE"
  fi
  chmod 600 "$ENV_FILE"
  export TELEGRAM_BOT_TOKEN
  echo "Saved to $ENV_FILE (chmod 600, gitignored)."
fi

# --- Pairing flow if no allowlist entries yet ---
needs_pairing=true
if [ -f "$ACCESS_FILE" ]; then
  if command -v jq >/dev/null 2>&1; then
    count=$(jq -r '.allowFrom // [] | length' "$ACCESS_FILE" 2>/dev/null || echo 0)
    [ "$count" -gt 0 ] && needs_pairing=false
  fi
fi

if [ "$needs_pairing" = true ]; then
  if ! command -v jq >/dev/null 2>&1; then
    echo "ERROR: jq required for pairing setup. Install with: brew install jq" >&2
    exit 1
  fi

  echo
  echo "No Telegram pairing found. Starting pairing flow..."
  echo "  1. Open Telegram and DM your bot any message."
  echo "  2. The bot will reply with a 6-character pairing code."
  echo "  3. Paste the code below."
  echo

  # Start the plugin server standalone so it polls Telegram. server.ts shuts
  # down on stdin EOF (orphan watchdog for when the MCP host disappears), so
  # we feed it stdin from a FIFO that we keep open via a held writer (sleep).
  # TELEGRAM_BOT_TOKEN and TELEGRAM_STATE_DIR are already exported.
  export TELEGRAM_BOT_TOKEN
  FIFO="$STATE_DIR/.pairing-fifo"
  rm -f "$FIFO"; mkfifo "$FIFO"
  # Hold the FIFO open for write so the server's stdin never sees EOF.
  sleep 999999 > "$FIFO" &
  HOLDER_PID=$!
  npx --prefix "$PLUGIN_DIR" tsx "$PLUGIN_DIR/server.ts" < "$FIFO" >/dev/null 2>&1 &
  BOT_PID=$!
  cleanup_pairing() {
    [ -n "${BOT_PID:-}" ] && kill "$BOT_PID" 2>/dev/null || true
    [ -n "${HOLDER_PID:-}" ] && kill "$HOLDER_PID" 2>/dev/null || true
    [ -n "${FIFO:-}" ] && rm -f "$FIFO"
  }
  trap cleanup_pairing EXIT INT TERM

  # Wait for the bot process to actually be polling — give it 5 seconds to settle.
  sleep 3
  if ! kill -0 "$BOT_PID" 2>/dev/null; then
    echo "ERROR: bot exited unexpectedly. Check token validity." >&2
    exit 1
  fi

  # Poll access.json for an emerging pending entry, with a timeout.
  echo "Waiting for you to DM the bot (up to ${PAIRING_TIMEOUT}s)..."
  end=$(( $(date +%s) + PAIRING_TIMEOUT ))
  pending_count=0
  while [ "$(date +%s)" -lt "$end" ]; do
    if [ -f "$ACCESS_FILE" ]; then
      pending_count=$(jq -r '.pending // {} | length' "$ACCESS_FILE" 2>/dev/null || echo 0)
      [ "$pending_count" -gt 0 ] && break
    fi
    sleep 2
  done

  if [ "$pending_count" -lt 1 ]; then
    echo "ERROR: timed out waiting for a Telegram message. Make sure the bot is running and you DM'd it." >&2
    exit 1
  fi

  # Prompt for the code; up to 3 tries.
  attempts=0
  while [ "$attempts" -lt 3 ]; do
    read -r -p "Paste the 6-char pairing code: " CODE
    CODE="$(echo "$CODE" | tr -d '[:space:]' | tr 'A-Z' 'a-z')"
    if jq -e --arg c "$CODE" '.pending[$c] // empty' "$ACCESS_FILE" >/dev/null 2>&1; then
      # Promote senderId to allowFrom and remove the pending entry. Atomic write.
      tmp=$(mktemp)
      jq --arg c "$CODE" '
        .allowFrom += [.pending[$c].senderId]
        | .allowFrom |= unique
        | del(.pending[$c])
      ' "$ACCESS_FILE" > "$tmp" && mv "$tmp" "$ACCESS_FILE"
      echo "✔ Paired."
      break
    fi
    attempts=$((attempts + 1))
    if [ "$attempts" -ge 3 ]; then
      echo "ERROR: invalid pairing code after 3 attempts." >&2
      exit 1
    fi
    echo "Code not found. Try again."
  done

  # Stop the standalone bot before Claude starts its own.
  cleanup_pairing
  wait "$BOT_PID" 2>/dev/null || true
  trap - EXIT INT TERM
  # Tiny pause so Telegram releases the poller.
  sleep 1
fi

# --- Launch ---
cd "$REPO_ROOT" && exec claude \
  --dangerously-load-development-channels "plugin:${PLUGIN_REF}" \
  --permission-mode bypassPermissions \
  --setting-sources user,project,local
