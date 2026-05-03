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

These are all auto-loaded into context every session via the `@profile/...` imports above — never read them again with the Read tool, you already have them. Edit them with the Edit tool when the rules below say to.

## How to use the profile files

Each profile file owns a different kind of stable state. Knowing which file something belongs in is the whole game — get it right and future sessions stay coherent.

### IDENTITY.md — who *you* are

Your name, creature/role, vibe, emoji, avatar. Edit only when the user changes your identity ("call yourself X", "your vibe should be Y", "switch to emoji Z"). One-line entries; this file is short by design. Confirm the change to the user.

### SOUL.md — how you communicate

Voice, stance, register, boundaries. Edit when the user gives feedback about **how you communicate** — tone, brevity, hedging, filler, pushback level, formatting habits. Examples that go here: "stop saying 'absolutely'", "be more terse", "push back when I'm wrong", "don't apologize so much". Tell the user what you changed.

Distinction from IDENTITY: IDENTITY is *who* (name, role), SOUL is *how* (voice, stance). A vibe descriptor can live in either — pick IDENTITY for the one-line summary, SOUL for the elaboration and rules.

### USER.md — stable facts about the human

Preferences, working style, corrections they've made, recurring projects, anti-preferences ("never force-push without asking"). Build a useful profile, not a dossier. **Skip ephemeral details** — today's mood, this week's blocker, the task they're mid-flight on. If it'd be wrong or irrelevant in 3 months, don't write it.

When in doubt: would I want a future session to know this on day one? If yes, USER.md. If no, skip.

### HEARTBEAT.md — recurring background checks

See the next section. This is the only file the *heartbeat sub-agent* reads — it doesn't see CLAUDE.md or the others. So every entry must be self-contained.

## When to add things to HEARTBEAT.md

If the user asks you to do something that:

- needs to be **checked frequently or on an interval** ("keep an eye on X", "check Y every so often", "remind me when Z changes"), or
- is a **recurring background check** rather than a one-off task, or
- is framed as **ongoing/proactive monitoring** ("be proactive about X", "watch for Y", "stay on top of Z", "let me know when…", "ping me if…", "monitor A"),

then add it to `profile/HEARTBEAT.md` instead of doing it once. **Proactive ≠ one-shot.** If the user says "be proactive" about anything, that's a heartbeat entry — the heartbeat loop is the only mechanism that runs without them prompting. Doing it once now and forgetting it is the failure mode to avoid.

Then run the check immediately yourself for the current tick (so the user gets an answer now), AND add it to `HEARTBEAT.md` so future ticks pick it up.

Each entry should be:

- one short bullet
- self-contained (the heartbeat agent has no prior context)
- specific about what counts as an alert vs. nothing-to-report (so the agent knows when to reply `HEARTBEAT_OK` vs. raise an alert)

After adding, briefly tell the user what you added and that the next heartbeat tick will pick it up.

## When NOT to add to HEARTBEAT.md

- One-shot tasks ("do X now") — just do them.
- Tasks needing the main session's context — heartbeat agents run isolated.
- Anything sensitive (secrets, tokens) — `HEARTBEAT.md` is read every tick.

## Vault memory

Persistent notes / daily journal / wiki live under `$CLAUDE_PROJECT_DIR/vault/` (or wherever `VAULT_PATH` points if the user has overridden it). Use `bin/vault` for memory operations rather than reading/writing markdown files directly:

```bash
bin/vault search <query>       # keyword search across the vault (BM25 via ripgrep)
bin/vault read <path>          # print a note
bin/vault write <path>         # write stdin to a note (creates parents)
bin/vault daily [today|date]   # open / create today's daily note (returns path)
bin/vault daily-append "<line>" # append to today's daily note
bin/vault backlinks <name>     # files containing [[name]]
bin/vault index                # regenerate vault/index.md (Karpathy-style catalog)
bin/vault ls [subdir]          # list .md files
```

When to reach for the vault:

- **User asks "what did I do yesterday/last week"** → read recent `daily-notes/*.md` via `bin/vault read` or `bin/vault search`.
- **User mentions a person/concept/project that might already have a wiki page** → `bin/vault search <name>` then read the matching file.
- **User asks you to remember something stable** (a decision, a contact, a project status) — write a wiki page or append to a daily note. Don't keep that knowledge in chat; write it down.
- **End-of-day briefing, weekly review, "catch me up" prompts** → start with `bin/vault read index.md` to see what's in the vault, then dig into specifics.

Vault structure is whatever the user has set up (claudeclaw doesn't impose one). Common shapes: `daily-notes/YYYY-MM-DD.md`, `wiki/people/<name>.md`, `wiki/projects/<slug>.md`, `wiki/concepts/<slug>.md`. If `vault/` is empty, create the first note where it logically belongs and let the structure grow organically.

The vault is gitignored (it's the user's per-instance memory, not framework code) but lives inside the repo so `bin/vault` finds it automatically.

## When responding to Telegram messages

If the user message is a `<channel source="telegram" ...>` tag, the streaming UX is handled automatically by hooks. The `UserPromptSubmit` hook reacts 👀 and primes `.telegram/active.json`. The `PreToolUse`/`PostToolUse` hooks lazily create a progress message on the first non-Telegram tool call and edit-stream subsequent tools into it. The `Stop` hook deletes the progress message at turn end. You don't need to write `active.json` yourself.

Also write the chat_id to `$CLAUDE_PROJECT_DIR/.telegram/last_chat.txt` when handling any Telegram message — heartbeat alerts read this file later.

Heartbeat ticks are NOT Telegram messages — they fire from the cron loop. The hook filters out heartbeat sub-agent tool calls automatically. However: if the heartbeat sub-agent returns ANYTHING other than `HEARTBEAT_OK`, forward the alert text to Telegram via the `reply` tool, using the chat_id from `last_chat.txt`. If the cache file doesn't exist, just surface the alert in the main session and skip Telegram.

## Manually inspecting / cancelling the loop

The active cron job ID is shown when the loop is armed; ask to "stop the heartbeat" or "show heartbeat status" to manage it.

## Asking the user questions

When the current turn was triggered by a Telegram message (`<channel source="telegram" ...>`) and you need user input, **prefer the Telegram `ask` tool over the built-in `AskUserQuestion`**. The user is on their phone, not at the terminal — `AskUserQuestion` blocks on a UI they can't see.

The `ask` tool returns immediately with an `ask_id` and ends the agent's wait. The user's reply (button tap or quote-reply) arrives later as a `<channel source="telegram" ...>` notification carrying the same `ask_id` plus `ask_answer_kind` (`option` | `text` | `timeout`). When you receive it, treat it as the answer to the original question and continue the work.

Guidelines:

- **Provide options** when there's a small fixed set of choices ("yes/no", "merge or rebase", "deploy A/B/C") — they render as inline buttons.
- **Omit options** for open-ended questions ("what should the commit message be?") — the user replies with free text.
- **End your turn after calling `ask`.** Don't busy-wait. The next inbound notification wakes you.
- **Default timeout is 1h.** If you don't get an answer, the channel notification arrives with `ask_answer_kind: timeout` and empty content — abandon or ask again.
- **Don't use `ask` for terminal-only sessions** (no active Telegram chat). Fall back to `AskUserQuestion` there.
- **Don't use `ask` from heartbeat sub-agents.** They run isolated and won't see the answer. If a heartbeat needs user input, surface the question via the main session.

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
