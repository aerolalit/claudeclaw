#!/usr/bin/env bash
# telegram-pre-compact.sh — PreCompact hook.
# Fires before Claude Code compacts session context (manual /compact or
# automatic). Last chance to digest pending turns into the vault before
# the in-context history is squashed.

set -u
if [ -n "${TELEGRAM_STATE_DIR:-}" ]; then
  TG_STATE_DIR="$TELEGRAM_STATE_DIR"
elif [ -n "${CLAUDE_PROJECT_DIR:-}" ] && [ -d "$CLAUDE_PROJECT_DIR/.telegram" ]; then
  TG_STATE_DIR="$CLAUDE_PROJECT_DIR/.telegram"
else
  TG_STATE_DIR="$HOME/.claude/channels/telegram"
fi
mkdir -p "$TG_STATE_DIR" 2>/dev/null || true
exec 2>>"$TG_STATE_DIR/stream.log"

HOOK_INPUT=$(cat 2>/dev/null || true)
export HOOK_INPUT
DIGEST_LIB="${CLAUDE_PROJECT_DIR:-$(pwd)}/.claude/hooks/lib/digest.sh"
if [ -f "$DIGEST_LIB" ]; then
  # shellcheck source=lib/digest.sh
  . "$DIGEST_LIB"
  digest_run "precompact" || true
fi

exit 0
