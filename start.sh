#!/usr/bin/env bash
# start.sh / claudeclaw — bootstrap and run the Telegram-channel session.
#
# Subcommands:
#   claudeclaw [start]        # default. Setup + launch (or attach if running).
#   claudeclaw stop           # kill the tmux session.
#   claudeclaw restart        # stop + start.
#   claudeclaw status         # show running state, PID, last heartbeat.
#   claudeclaw attach         # tmux attach to the running session.
#   claudeclaw logs [-f]      # tail .telegram/stream.log.
#   claudeclaw update         # git pull + reinstall plugin if changed.
#   claudeclaw doctor         # diagnostic: deps, auth, tokens, network.
#   claudeclaw disconnect <channel>  # clear bot token + pairing for a channel.
#                                    # Supported channels: telegram
#   claudeclaw uninstall      # remove the ~/.local/bin/claudeclaw symlink.
#   claudeclaw uninstall --purge  # also delete the cloned repo.
#   claudeclaw version        # print version.
#   claudeclaw help           # this help.
#
# Flags (apply to start):
#   --no-tg                   # launch without Telegram channel (terminal only).
#
# First run does (all foreground, interactive):
#   1. Install Claude Code (if missing) via the official installer.
#   2. Walk through auth (interactive token paste for headless setups).
#   3. Install plugin npm deps.
#   4. Register the local "claudeclaw" plugin marketplace.
#   5. Install the telegram plugin from that marketplace.
#   6. Prompt for TELEGRAM_BOT_TOKEN; save to .env (chmod 600, gitignored).
#   7. If no Telegram allowlist entries exist, run the pairing flow.
#
# Subsequent runs detect prior setup and skip these steps.
#
# ─── Running on a server / surviving SSH disconnect ───
#
# Claude Code is interactive and must be attached to a TTY. To keep it
# running after SSH disconnect, wrap it in tmux on the SERVER:
#
#   ssh user@server
#   tmux new -s claudeclaw 'cd ~/claudeclawpi && ./start.sh'
#   # press Enter on the dev-channels prompt when it appears
#   # detach: Ctrl+B then D
#   # close terminal — Claude keeps running on the server
#
#   # tomorrow:
#   ssh user@server
#   tmux attach -t claudeclaw
#
# Apt:  sudo apt install -y tmux
# Brew: brew install tmux
#
# ─── To pick up local edits to plugins/telegram/server.ts ───
#
# Inside Claude:
#   /plugin marketplace update claudeclaw
#   /plugin uninstall telegram@claudeclaw
#   /plugin install telegram@claudeclaw

set -euo pipefail

# Make sure common user-bin paths are on PATH — non-interactive shells
# (e.g. curl-pipe-bash, ssh -c) don't source .bashrc, so they miss these.
for bin_dir in "$HOME/.local/bin" "$HOME/bin" "$HOME/.npm-global/bin"; do
  case ":$PATH:" in *:"$bin_dir":*) ;; *) [ -d "$bin_dir" ] && PATH="$bin_dir:$PATH" ;; esac
done
export PATH

# Resolve $0 through any symlinks (e.g. ~/.local/bin/claudeclaw -> the real
# script in the cloned repo) so REPO_ROOT points at the actual repo, not the
# symlink dir. POSIX-portable readlink-loop — works on macOS (BSD readlink
# without -f) and Linux alike.
self="$0"
while [ -L "$self" ]; do
  link_target="$(readlink "$self")"
  case "$link_target" in
    /*) self="$link_target" ;;
    *)  self="$(cd "$(dirname "$self")" && pwd)/$link_target" ;;
  esac
done
REPO_ROOT="$(cd "$(dirname "$self")" && pwd)"
PLUGIN_DIR="$REPO_ROOT/plugins/telegram"
MARKETPLACE_NAME="claudeclaw"
PLUGIN_REF="telegram@${MARKETPLACE_NAME}"
ENV_FILE="$REPO_ROOT/.env"
# All Telegram state (access.json, .env, bot.pid, inbox/) lives inside the
# repo so this workspace owns its own bot and pairing — nothing in $HOME.
# Picked up by the plugin via TELEGRAM_STATE_DIR (see server.ts).
STATE_DIR="$REPO_ROOT/.telegram"
ACCESS_FILE="$STATE_DIR/access.json"
TMUX_SESSION="claudeclaw"
PAIRING_TIMEOUT=180  # seconds to wait for user to DM the bot

mkdir -p "$STATE_DIR"
chmod 700 "$STATE_DIR" 2>/dev/null || true

# Scaffold the vault dir (Karpathy layout: raw/, wiki/{people,concepts,
# projects,entities}, daily-notes/, plus log.md and index.md). Idempotent.
# User's per-instance memory; gitignored. Honours VAULT_PATH if set.
"$REPO_ROOT/bin/vault" scaffold >/dev/null 2>&1 || true

LOG_FILE="$STATE_DIR/stream.log"

# ────────────────────────────────────────────────────────────────────
# Subcommand functions
# ────────────────────────────────────────────────────────────────────

cmd_help() {
  sed -n '/^# start\.sh/,/^$/p' "$self" | sed 's/^# \?//'
}

cmd_version() {
  local v="(unknown)"
  if [ -d "$REPO_ROOT/.git" ]; then
    v=$(cd "$REPO_ROOT" && git describe --tags --always --dirty 2>/dev/null || echo "(no tags)")
  fi
  echo "claudeclaw $v"
  echo "  repo: $REPO_ROOT"
  command -v claude >/dev/null 2>&1 && claude --version 2>/dev/null | head -1 | sed 's/^/  /' || true
}

cmd_attach() {
  if ! command -v tmux >/dev/null 2>&1; then
    echo "ERROR: tmux not installed." >&2; exit 1
  fi
  if ! tmux has-session -t "$TMUX_SESSION" 2>/dev/null; then
    echo "Not running. Start with: claudeclaw start" >&2; exit 1
  fi
  exec tmux attach -t "$TMUX_SESSION"
}

cmd_status() {
  echo "claudeclaw"
  echo "  repo:  $REPO_ROOT"
  echo "  state: $STATE_DIR"
  echo
  if command -v tmux >/dev/null 2>&1 && tmux has-session -t "$TMUX_SESSION" 2>/dev/null; then
    echo "  tmux session: ✓ running ($TMUX_SESSION)"
    echo "  attach with:  claudeclaw attach"
  else
    echo "  tmux session: ✗ not running"
    echo "  start with:   claudeclaw start"
  fi
  echo
  if [ -s "$LOG_FILE" ]; then
    echo "  last log line: $(tail -1 "$LOG_FILE")"
  else
    echo "  no log activity yet"
  fi
  echo
  if [ -f "$ENV_FILE" ] && grep -q '^TELEGRAM_BOT_TOKEN=' "$ENV_FILE"; then
    echo "  bot token: ✓ set"
  else
    echo "  bot token: ✗ missing (.env)"
  fi
  if [ -f "$ACCESS_FILE" ] && command -v jq >/dev/null 2>&1; then
    local n
    n=$(jq -r '.allowFrom // [] | length' "$ACCESS_FILE" 2>/dev/null || echo 0)
    if [ "$n" -gt 0 ]; then
      echo "  paired:    ✓ $n sender(s) on allowlist"
    else
      echo "  paired:    ✗ no allowlist entries"
    fi
  fi
}

cmd_stop() {
  if ! command -v tmux >/dev/null 2>&1 || ! tmux has-session -t "$TMUX_SESSION" 2>/dev/null; then
    echo "Not running."
    _kill_stale_bot
    return 0
  fi
  tmux kill-session -t "$TMUX_SESSION"
  echo "✔ stopped (killed tmux session: $TMUX_SESSION)"
  _kill_stale_bot
}

# Kill any bot process recorded in bot.pid, then wait for Telegram to release
# the long-poll connection (avoids 409 Conflict on rapid restart).
_kill_stale_bot() {
  local pid_file="$STATE_DIR/bot.pid"
  local old_pid=""
  [ -f "$pid_file" ] && old_pid=$(cat "$pid_file" 2>/dev/null)
  if [ -n "$old_pid" ] && kill -0 "$old_pid" 2>/dev/null; then
    echo "  killing stale bot (PID $old_pid)..."
    kill "$old_pid" 2>/dev/null || true
  fi
  rm -f "$pid_file"
  # Give Telegram ~2 s to release the long-poll connection before we allow
  # a new bot to start — prevents 409 Conflict on rapid restart.
  sleep 2
}

cmd_restart() {
  cmd_stop
  exec "$self" start "$@"
}

cmd_logs() {
  [ ! -f "$LOG_FILE" ] && { echo "No log file yet at $LOG_FILE"; exit 0; }
  case "${1:-}" in
    -f|--follow) tail -f "$LOG_FILE" ;;
    *)           tail -50 "$LOG_FILE" ;;
  esac
}

cmd_update() {
  cd "$REPO_ROOT"
  if [ ! -d .git ]; then
    echo "ERROR: $REPO_ROOT is not a git checkout. Reinstall: ${0##*/}" >&2
    exit 1
  fi
  echo "→ pulling latest..."
  git pull --ff-only
  echo
  echo "→ updating npm deps if package.json changed..."
  if [ -f "$PLUGIN_DIR/package.json" ] && [ -d "$PLUGIN_DIR/node_modules" ]; then
    (cd "$PLUGIN_DIR" && npm install --silent --no-audit --no-fund) || true
  fi
  echo
  echo "→ reinstalling Claude Code plugin so server.ts changes take effect..."
  if command -v claude >/dev/null 2>&1; then
    claude plugin marketplace update "$MARKETPLACE_NAME" 2>&1 | tail -3 || true
    claude plugin uninstall "$PLUGIN_REF" 2>&1 | tail -1 || true
    echo "y" | claude plugin install "$PLUGIN_REF" --scope project 2>&1 | tail -1 || true
  fi
  echo
  echo "✔ updated. Restart your session: claudeclaw restart"
}

cmd_doctor() {
  local ok=0 fail=0
  check() {
    if eval "$2" >/dev/null 2>&1; then
      printf "  ✓ %s\n" "$1"; ok=$((ok+1))
    else
      printf "  ✗ %s\n" "$1"; fail=$((fail+1))
    fi
  }
  echo "claudeclaw doctor"
  echo
  echo "Dependencies:"
  check "node 18+ on PATH"        'command -v node && [ "$(node -v | sed s/v// | cut -d. -f1)" -ge 18 ]'
  check "npm on PATH"             'command -v npm'
  check "git on PATH"             'command -v git'
  check "tmux on PATH"            'command -v tmux'
  check "jq on PATH"              'command -v jq'
  check "curl on PATH"            'command -v curl'
  echo
  echo "Claude Code:"
  check "claude on PATH"          'command -v claude'
  check ".credentials.json"       '[ -s "$HOME/.claude/.credentials.json" ]'
  check "onboarding complete"     'grep -q "\"hasCompletedOnboarding\"[[:space:]]*:[[:space:]]*true" "$HOME/.claude.json"'
  check "marketplace registered"  'claude plugin marketplace list 2>/dev/null | grep -qE "[❯>][[:space:]]+$MARKETPLACE_NAME[[:space:]]*$"'
  check "plugin installed"        'claude plugin list 2>/dev/null | grep -qE "[❯>][[:space:]]+$PLUGIN_REF([[:space:]]|$)"'
  echo
  echo "Telegram:"
  check ".env present"            '[ -f "$ENV_FILE" ]'
  check "bot token set"           'grep -q "^TELEGRAM_BOT_TOKEN=." "$ENV_FILE" 2>/dev/null'
  check "access.json present"     '[ -f "$ACCESS_FILE" ]'
  check "≥1 allowlist entry"      '[ "$(jq -r ".allowFrom // [] | length" "$ACCESS_FILE" 2>/dev/null)" -gt 0 ]'
  check "api.telegram.org reachable" 'curl -fsS --max-time 5 https://api.telegram.org/ >/dev/null 2>&1 || curl -fsS --max-time 5 https://api.telegram.org -o /dev/null -w "%{http_code}" | grep -qE "^(2|3|4)"'
  echo
  echo "Plugin:"
  check "node_modules present"    '[ -d "$PLUGIN_DIR/node_modules" ]'
  check "server.ts present"       '[ -f "$PLUGIN_DIR/server.ts" ]'
  echo
  echo "Runtime:"
  check "tmux session running"    'tmux has-session -t "$TMUX_SESSION" 2>/dev/null'
  echo
  echo "Result: $ok passed, $fail failed"
  [ "$fail" -gt 0 ] && return 1 || return 0
}

# --- Channel registry ----------------------------------------------------
# Each supported channel has a `disconnect_<channel>` function. To add
# another channel later, register it here and implement the function.
SUPPORTED_CHANNELS="telegram"

disconnect_telegram() {
  echo "→ Disconnecting Telegram channel..."

  # 1. Stop running session.
  if command -v tmux >/dev/null 2>&1 && tmux has-session -t "$TMUX_SESSION" 2>/dev/null; then
    tmux kill-session -t "$TMUX_SESSION"
    echo "  ✓ stopped tmux session"
  fi

  # 2. Strip TELEGRAM_BOT_TOKEN from .env (preserve other lines like CLAUDE_CODE_OAUTH_TOKEN).
  if [ -f "$ENV_FILE" ] && grep -q "^TELEGRAM_BOT_TOKEN=" "$ENV_FILE"; then
    sed -i.bak "/^TELEGRAM_BOT_TOKEN=/d" "$ENV_FILE" && rm -f "$ENV_FILE.bak"
    echo "  ✓ removed TELEGRAM_BOT_TOKEN from .env"
  fi

  # 3. Reset access.json to defaults — wipe pairings + pending codes.
  if [ -f "$ACCESS_FILE" ]; then
    cat > "$ACCESS_FILE" <<'EOF'
{
  "dmPolicy": "pairing",
  "allowFrom": [],
  "groups": {},
  "pending": {}
}
EOF
    chmod 600 "$ACCESS_FILE"
    echo "  ✓ reset $ACCESS_FILE"
  fi

  echo
  echo "✔ Telegram disconnected. To reconnect, run: claudeclaw"
  echo
  echo "Note: this did NOT revoke the bot on Telegram's side. To fully"
  echo "      revoke the bot token, DM @BotFather and run /revoke."
}

cmd_disconnect() {
  local channel="${1:-}"
  local force=false
  shift 2>/dev/null || true
  for arg in "$@"; do
    case "$arg" in --force|-f) force=true ;; esac
  done

  if [ -z "$channel" ]; then
    cat >&2 <<EOF
ERROR: specify a channel.

  Usage:  claudeclaw disconnect <channel>
  Supported channels: $SUPPORTED_CHANNELS

EOF
    return 2
  fi

  case " $SUPPORTED_CHANNELS " in
    *" $channel "*) ;;
    *)
      echo "ERROR: unknown channel '$channel'. Supported: $SUPPORTED_CHANNELS" >&2
      return 2
      ;;
  esac

  if [ "$force" != "true" ]; then
    case "$channel" in
      telegram)
        cat <<EOF

This will:
  • Stop the running session (if any)
  • Clear the Telegram bot token from .env
  • Reset the Telegram pairing allowlist (.telegram/access.json)

Note: this does NOT revoke the bot on Telegram's side. To do that,
DM @BotFather and run /revoke.

EOF
        ;;
    esac
    read -r -p "Continue? [y/N]: " confirm
    case "${confirm:-N}" in
      [yY]|[yY][eE][sS]) ;;
      *) echo "Cancelled."; return 0 ;;
    esac
  fi

  "disconnect_${channel}"
}

cmd_uninstall() {
  local purge=false
  case "${1:-}" in --purge|-p) purge=true ;; esac

  if command -v tmux >/dev/null 2>&1 && tmux has-session -t "$TMUX_SESSION" 2>/dev/null; then
    echo "→ stopping running session..."
    tmux kill-session -t "$TMUX_SESSION"
  fi

  local shim="$HOME/.local/bin/claudeclaw"
  if [ -L "$shim" ]; then
    rm -f "$shim"
    echo "✔ removed shim: $shim"
  else
    echo "  (no shim at $shim)"
  fi

  if [ "$purge" = true ]; then
    if [ -d "$REPO_ROOT" ]; then
      echo "→ deleting repo: $REPO_ROOT"
      rm -rf "$REPO_ROOT"
      echo "✔ purged"
    fi
  else
    echo
    echo "Repo at $REPO_ROOT was NOT deleted (contains your .env, pairing, profile)."
    echo "  To delete it: claudeclaw uninstall --purge"
  fi
}

# ────────────────────────────────────────────────────────────────────
# Dispatcher
# ────────────────────────────────────────────────────────────────────

# NOTE: `shift` under `set -u` errors when $# is 0. Guard each shift with $#>0.
case "${1:-start}" in
  start)            [ $# -gt 0 ] && shift; ;;  # fall through to the main flow below
  stop)             cmd_stop;     exit $? ;;
  restart)          [ $# -gt 0 ] && shift; cmd_restart "$@"; exit $? ;;
  status)           cmd_status;   exit $? ;;
  attach)           cmd_attach;   exit $? ;;
  logs)             [ $# -gt 0 ] && shift; cmd_logs "$@"; exit $? ;;
  update)           cmd_update;   exit $? ;;
  doctor)           cmd_doctor;   exit $? ;;
  disconnect)       [ $# -gt 0 ] && shift; cmd_disconnect "$@"; exit $? ;;
  uninstall)        [ $# -gt 0 ] && shift; cmd_uninstall "$@"; exit $? ;;
  version|--version|-v) cmd_version; exit 0 ;;
  help|--help|-h)   cmd_help;     exit 0 ;;
  --no-tg)          ;;  # known flag for `start` — no-op here, parsed below
  -*)               echo "ERROR: unknown flag: $1" >&2; cmd_help; exit 2 ;;
  *)                echo "ERROR: unknown subcommand: $1" >&2; cmd_help; exit 2 ;;
esac

# ────────────────────────────────────────────────────────────────────
# Main `start` flow (default subcommand) — original behavior follows
# ────────────────────────────────────────────────────────────────────

# --- If a claudeclaw tmux session is already running, offer to reattach ---
# Skip this check if we're already inside tmux (the script may be re-execing
# itself from the tmux-wrap branch below).
if [ -z "${TMUX:-}" ] && command -v tmux >/dev/null 2>&1 && \
   tmux has-session -t "$TMUX_SESSION" 2>/dev/null; then
  cat <<EOF

A claudeclaw tmux session is already running.

  [1] Reattach (default)             — connect to the running Claude session
  [2] Kill it and start fresh        — tear down and re-run setup
  [3] Cancel                         — exit without doing anything

EOF
  read -r -p "Choice [1/2/3] (default 1): " session_choice
  case "${session_choice:-1}" in
    2|k|K|kill)
      tmux kill-session -t "$TMUX_SESSION"
      echo "✔ killed session '$TMUX_SESSION' — continuing with fresh setup..."
      ;;
    3|c|C|cancel|n|N)
      echo "Cancelled."
      exit 0
      ;;
    *)
      exec tmux attach -t "$TMUX_SESSION"
      ;;
  esac
fi

# --- Parse flags ---
NO_TG=false
for arg in "$@"; do
  case "$arg" in
    --no-tg) NO_TG=true ;;
    --help|-h)
      sed -n '/^# start\.sh/,/^$/p' "$0" | sed 's/^# \?//'
      exit 0
      ;;
  esac
done

# --- Load repo-local .env if present ---
# Parse line-by-line instead of `source`-ing — shell-special chars (parens,
# backticks, $, etc.) inside values would otherwise be interpreted as syntax
# and break the load. Format: KEY=VALUE, no quoting, no shell interpolation.
# Lines starting with # or empty are skipped.
if [ -f "$ENV_FILE" ]; then
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      ''|\#*) continue ;;
      [A-Za-z_]*=*)
        key="${line%%=*}"
        value="${line#*=}"
        # Trust the file; just export. No shell expansion of value.
        export "$key=$value"
        ;;
    esac
  done < "$ENV_FILE"
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

Generate a long-lived auth token from any machine with a browser:

  1. On that machine, run:  claude setup-token
  2. Sign in to claude.ai when prompted
  3. Copy the long token it prints

(Requires a Claude Pro / Max / Team subscription. Token valid ~1 year.
 Prefer browser login on this machine instead? Ctrl+C, run `claude
 login`, then re-run claudeclaw.)

EOF
  # Silent input — token doesn't echo, doesn't land in scrollback or session logs.
  read -rs -p "Paste the setup-token here (input hidden): " setup_token
  echo  # newline after silent read so the next message starts on its own line
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
if [ "$NO_TG" = "true" ]; then
  cd "$REPO_ROOT" && exec claude
fi

# --- Prompt for bot token if missing ---
if [ -z "${TELEGRAM_BOT_TOKEN:-}" ]; then
  echo
  echo "Telegram bot token not configured."
  echo "  Get one from @BotFather on Telegram (/newbot)."
  echo
  # Silent input — token doesn't echo, doesn't land in scrollback or session logs.
  read -rs -p "Paste your bot token (input hidden): " TELEGRAM_BOT_TOKEN
  echo
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

# --- Optional: wrap launch in tmux so it survives terminal close ---
# Skip if we're already inside a tmux session (this is the re-exec from the
# wrapper below, or the user runs from inside their own tmux).
# (Existing-session collision is handled at script entry — we'd have either
#  reattached or killed it before reaching here.)
if [ -z "${TMUX:-}" ]; then
  cat <<'EOF'

Should claudeclaw keep running after you close this terminal?
  [1] Yes — survives terminal close, SSH disconnect, etc.   [recommended]
         (Uses a tool called "tmux" under the hood — auto-installs if needed.
          Reattach later with: tmux attach -t claudeclaw)

  [2] No  — runs only in this terminal. Closes when you close it.

EOF
  read -r -p "Choice [1/2] (default 1): " tmux_choice
  case "${tmux_choice:-1}" in
    1|y|Y|yes)
      # Install tmux if missing.
      if ! command -v tmux >/dev/null 2>&1; then
        echo "tmux not installed — installing..."
        if command -v apt-get >/dev/null 2>&1; then
          sudo apt-get install -y tmux
        elif command -v brew >/dev/null 2>&1; then
          brew install tmux
        elif command -v dnf >/dev/null 2>&1; then
          sudo dnf install -y tmux
        elif command -v pacman >/dev/null 2>&1; then
          sudo pacman -S --noconfirm tmux
        elif command -v apk >/dev/null 2>&1; then
          sudo apk add tmux
        else
          echo "ERROR: no known package manager (apt/brew/dnf/pacman/apk)." >&2
          echo "  Install tmux manually, then re-run ./start.sh." >&2
          exit 1
        fi
      fi
      # Re-exec ourselves inside a new tmux session.
      # The TMUX env var is now set inside that session, so this branch is skipped on the relaunch.
      echo
      echo "Launching inside tmux session '$TMUX_SESSION'."
      echo "  Detach (leave running): Ctrl+B then D"
      echo "  Reattach later:         tmux attach -t $TMUX_SESSION"
      exec tmux new-session -s "$TMUX_SESSION" "$0"
      ;;
  esac
fi

# --- Kill any stale bot before launching (prevents 409 Conflict) ---
_kill_stale_bot

# --- Launch (foreground, attached to terminal or tmux session) ---
cd "$REPO_ROOT" && exec claude \
  --dangerously-load-development-channels "plugin:${PLUGIN_REF}" \
  --permission-mode bypassPermissions \
  --setting-sources user,project,local
