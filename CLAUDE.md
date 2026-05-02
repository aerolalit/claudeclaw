# Claudeclaw — Heartbeat Workspace

This folder runs a recurring heartbeat loop (configured in `.claude/settings.json`). Every 30 minutes a subagent reads `profile/HEARTBEAT.md` and executes whatever instructions it contains, replying `HEARTBEAT_OK` if nothing needs attention.

## First-run bootstrap

If `profile/BOOTSTRAP.md` exists, **read it FIRST and run the interview conversation before doing anything else.** This is a fresh template clone — `IDENTITY.md`, `USER.md`, and `SOUL.md` in `profile/` are unpopulated and need to be filled in conversationally with the user.

When the interview is complete:

1. Update `profile/IDENTITY.md`, `profile/USER.md`, `profile/SOUL.md` (and optionally `profile/HEARTBEAT.md`) with what you learned.
2. Delete `profile/BOOTSTRAP.md` — its absence signals onboarding is done.
3. Welcome the user to the workspace and tell them about the heartbeat loop.

If `profile/BOOTSTRAP.md` does not exist, skip straight to normal operation.

## Workspace files (read these every session)

- @profile/IDENTITY.md — who you are (name, vibe, emoji).
- @profile/SOUL.md — your voice, stance, and style. This is how you communicate.
- @profile/USER.md — facts about the human. Update as you learn.
- @profile/HEARTBEAT.md — recurring checks executed every 30 min (do **not** treat this as your task list — it's the heartbeat agent's, not yours).

## When to update SOUL.md

If the user gives you feedback that's about **how you communicate** (tone, brevity, hedging, filler words, voice), update `profile/SOUL.md` so the change persists across sessions. Tell the user what you changed.

## When to update USER.md

When you learn something stable about the user — preferences, working style, things they've corrected you on, recurring projects — add it to `profile/USER.md`. Don't dump everything; build a useful profile, not a dossier. Skip ephemeral details (today's mood, this week's task).

## When to add things to HEARTBEAT.md

If the user asks you to do something that:

- needs to be **checked frequently or on an interval** ("keep an eye on X", "check Y every so often", "remind me when Z changes"), or
- is a **recurring background check** rather than a one-off task,

then add it to `profile/HEARTBEAT.md` instead of doing it once.

Each entry should be:

- one short bullet
- self-contained (the heartbeat agent has no prior context)
- specific about what counts as an alert vs. nothing-to-report (so the agent knows when to reply `HEARTBEAT_OK` vs. raise an alert)

After adding, briefly tell the user what you added and that the next heartbeat tick will pick it up.

## When NOT to add to HEARTBEAT.md

- One-shot tasks ("do X now") — just do them.
- Tasks needing the main session's context — heartbeat agents run isolated.
- Anything sensitive (secrets, tokens) — `HEARTBEAT.md` is read every tick.

## When responding to Telegram messages

If the user message is a `<channel source="telegram" ...>` tag, the streaming UX is handled automatically by hooks. The `UserPromptSubmit` hook reacts 👀 and primes `.telegram/active.json`. The `PreToolUse`/`PostToolUse` hooks lazily create a progress message on the first non-Telegram tool call and edit-stream subsequent tools into it. The `Stop` hook deletes the progress message at turn end. You don't need to write `active.json` yourself.

Also write the chat_id to `$CLAUDE_PROJECT_DIR/.telegram/last_chat.txt` when handling any Telegram message — heartbeat alerts read this file later.

Heartbeat ticks are NOT Telegram messages — they fire from the cron loop. The hook filters out heartbeat sub-agent tool calls automatically. However: if the heartbeat sub-agent returns ANYTHING other than `HEARTBEAT_OK`, forward the alert text to Telegram via the `reply` tool, using the chat_id from `last_chat.txt`. If the cache file doesn't exist, just surface the alert in the main session and skip Telegram.

## Manually inspecting / cancelling the loop

The active cron job ID is shown when the loop is armed; ask to "stop the heartbeat" or "show heartbeat status" to manage it.

## File map (quick reference)

| File | Purpose | Tracked? | Loaded how |
|------|---------|----------|------------|
| `CLAUDE.md` | Framework instructions (this file) | yes | Auto on session start |
| `README.md` | Template usage docs | yes | — |
| `.claude/settings.json` | Permissions + hooks | yes | Auto by Claude Code |
| `.claude/hooks/telegram-*.sh` | Pre/PostToolUse + UserPromptSubmit + Stop + SessionEnd hooks for Telegram streaming | yes | Invoked by Claude Code on the matching event |
| `templates/*.md` | Tracked templates for the personal files in `profile/` | yes | Copied into `profile/` by the SessionStart hook when missing |
| `profile/BOOTSTRAP.md` | First-run interview script | no (gitignored) | Read on session 1, then deleted |
| `profile/IDENTITY.md` | Your name, vibe, emoji | no (gitignored) | Imported via `@profile/IDENTITY.md` above |
| `profile/SOUL.md` | Voice, stance, personality | no (gitignored) | Imported via `@profile/SOUL.md` above |
| `profile/USER.md` | Facts about the human | no (gitignored) | Imported via `@profile/USER.md` above |
| `profile/HEARTBEAT.md` | Recurring checks for the heartbeat loop | no (gitignored) | Read by subagent every 30 min |
| `plugins/telegram/` | Forked Telegram channel plugin | yes | Installed by `start.sh` from local marketplace |
| `.env` / `.env.example` | Bot token and other secrets — only `.example` is tracked | no | Loaded by `start.sh` |
| `.telegram/` | Repo-local Telegram state (access.json, bot.pid) | no (gitignored) | Read by plugin and hooks via `TELEGRAM_STATE_DIR` |

The `profile/` directory is gitignored so framework updates pulled via `git pull` never conflict with per-instance content. New `templates/*.md` files added in framework updates auto-materialize into `profile/` on next session start.
