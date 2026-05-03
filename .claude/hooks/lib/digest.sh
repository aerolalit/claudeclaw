#!/usr/bin/env bash
# .claude/hooks/lib/digest.sh — shared helper sourced by Stop / PreCompact /
# SessionEnd hooks. Spawns a digest sub-agent (fire-and-forget) to extract
# durable facts from the conversation transcript and write them to the vault.
#
# The digest is bookmark-driven: each run reads .telegram/digest-bookmark
# to know where to start, processes from there to end-of-transcript, and
# advances the bookmark. Idempotent — three hooks sharing one bookmark
# means whichever fires first wins; the others find no new content and exit.
#
# Cost: trivial turns (combined diff < $DIGEST_MIN_BYTES) skip the spawn.
# The sub-agent uses Haiku via `claude -p` for cost; main session is unaffected.
#
# Usage from a hook:
#   . "$CLAUDE_PROJECT_DIR/.claude/hooks/lib/digest.sh"
#   digest_run "stop"
#
# Logs to .telegram/digest.log so failures don't pollute stream.log.

DIGEST_MIN_BYTES="${DIGEST_MIN_BYTES:-1024}"   # skip if new content under 1KB
DIGEST_MAX_BYTES="${DIGEST_MAX_BYTES:-65536}"  # cap input to ~64KB to bound cost
DIGEST_MODEL="${DIGEST_MODEL:-haiku}"          # cheap sub-agent

digest_run() {
  local source="${1:-unknown}"
  local repo_root="${CLAUDE_PROJECT_DIR:-$(pwd)}"
  local state_dir="${TELEGRAM_STATE_DIR:-$repo_root/.telegram}"
  local vault_dir="${VAULT_PATH:-$repo_root/vault}"
  local prompt_file="$repo_root/templates/digest-prompt.md"
  local bookmark="$state_dir/digest-bookmark"
  local digest_log="$state_dir/digest.log"

  # Bail fast if any prereq is missing — silent, don't block the agent.
  [ -f "$prompt_file" ] || { echo "[$(date -Iseconds)] [$source] no digest prompt at $prompt_file — skipping" >> "$digest_log"; return 0; }
  [ -d "$vault_dir" ] || { echo "[$(date -Iseconds)] [$source] no vault dir — skipping" >> "$digest_log"; return 0; }
  command -v claude >/dev/null 2>&1 || { echo "[$(date -Iseconds)] [$source] no claude on PATH — skipping" >> "$digest_log"; return 0; }

  # Need transcript_path from hook stdin. Caller has already read INPUT;
  # we re-parse it here so this helper is self-contained.
  local transcript_path
  transcript_path=$(echo "${HOOK_INPUT:-}" | jq -r '.transcript_path // empty' 2>/dev/null)
  [ -z "$transcript_path" ] || [ ! -f "$transcript_path" ] && return 0

  # Read bookmark (last byte offset processed). Default to 0 if missing.
  local last_offset=0
  [ -f "$bookmark" ] && last_offset=$(cat "$bookmark" 2>/dev/null || echo 0)

  # Current transcript size.
  local current_size
  current_size=$(wc -c < "$transcript_path" 2>/dev/null | tr -d ' ')
  [ -z "$current_size" ] && return 0

  # Nothing new since last digest? Exit silently.
  local new_bytes=$(( current_size - last_offset ))
  if [ "$new_bytes" -lt "$DIGEST_MIN_BYTES" ]; then
    return 0
  fi

  # Cap how much we ship to the sub-agent. If transcript advanced more than
  # DIGEST_MAX_BYTES, only digest the most recent window — older content
  # was either already digested or lost. This bounds cost on long sessions.
  local start_offset="$last_offset"
  if [ "$new_bytes" -gt "$DIGEST_MAX_BYTES" ]; then
    start_offset=$(( current_size - DIGEST_MAX_BYTES ))
  fi

  # Extract the relevant byte range. tail -c gives us "last N bytes."
  local excerpt
  excerpt=$(tail -c "+$((start_offset + 1))" "$transcript_path" 2>/dev/null | head -c "$DIGEST_MAX_BYTES")
  [ -z "$excerpt" ] && return 0

  # Build the prompt: meta-instructions + the excerpt.
  local prompt_body
  prompt_body=$(cat "$prompt_file")

  local full_prompt
  full_prompt="$prompt_body

---

You were called with source: \"$source\".

Conversation excerpt to digest (most recent transcript range, JSONL format):

\`\`\`jsonl
$excerpt
\`\`\`
"

  # Fire the sub-agent in the background. Don't wait on it — the agent
  # returns immediately, the digest happens out of band.
  # cd into repo so bin/vault resolves correctly inside the sub-agent.
  (
    cd "$repo_root"
    echo "$full_prompt" | claude -p \
      --model "$DIGEST_MODEL" \
      --permission-mode bypassPermissions \
      --setting-sources project,local \
      --add-dir "$vault_dir" \
      >> "$digest_log" 2>&1
    echo "[$(date -Iseconds)] [$source] digest complete (${new_bytes}B → cap ${DIGEST_MAX_BYTES}B)" >> "$digest_log"
  ) &
  disown 2>/dev/null || true

  # Advance the bookmark immediately. If the sub-agent fails, we lose this
  # range from the digest — acceptable trade for not blocking the hook.
  echo "$current_size" > "$bookmark"

  return 0
}
