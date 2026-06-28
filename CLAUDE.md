# Claudeclaw — Scheduled Task Workspace

This folder is a Claude Code workspace with a general-purpose scheduled task system. Recurring tasks run via OS cron, each appending results to `.tasks/results.log`. The main session watches that file via a persistent `Monitor` (armed on every session start), so results land in session context and can be discussed interactively.

## First-run bootstrap

If `profile/BOOTSTRAP.md` exists, **read it FIRST and run the interview conversation before doing anything else.** This is a fresh template clone — `IDENTITY.md`, `USER.md`, and `SOUL.md` in `profile/` are unpopulated and need to be filled in conversationally with the user.

When the interview is complete:

1. Update `profile/IDENTITY.md`, `profile/USER.md`, `profile/SOUL.md`, `profile/MEMORY.md` with what you learned.
2. Delete `profile/BOOTSTRAP.md` — its absence signals onboarding is done.
3. Welcome the user to the workspace and tell them about the scheduled task system.

If `profile/BOOTSTRAP.md` does not exist, skip straight to normal operation.

## Workspace files (read these every session)

- @profile/IDENTITY.md — who you are (name, vibe, emoji).
- @profile/SOUL.md — your voice, stance, and style. This is how you communicate.
- @profile/USER.md — facts about the human. Update as you learn.
- @profile/MEMORY.md — long-term operational memory: user facts, feedback you've been given, project context, external references. Update as you learn.

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

### MEMORY.md — long-term operational memory

Persistent notes that keep future sessions coherent, under four headings — **User**, **Feedback**, **Project**, **Reference**. This whole file is auto-loaded every session, so **keep entries terse** (a line or two) and **prune what's stale**.

Write to it when:

- you learn something durable about the user — role, expertise, goals, working style → **User** (a short pointer; the full profile is `USER.md`, don't duplicate it)
- the user corrects your approach **or** confirms a non-obvious one worked ("yes, exactly", accepting an unusual choice without pushback) → **Feedback** — lead with the rule, then a brief *why* so you can judge edge cases later
- you learn who's doing what / why / by when on the project → **Project** (convert relative dates to absolute; this decays fast — prune aggressively)
- you learn where something lives in an external system — issue tracker, dashboard, repo, Slack channel → **Reference**

Don't store here: code patterns, file paths, project structure, git history, debugging recipes — anything derivable from reading the repo. When in doubt: "would a future session want this on day one?" yes → MEMORY.md, no → skip.

**This is the workspace's memory** — it replaces the default `~/.claude/projects/.../memory/` location your base instructions may mention; use `profile/MEMORY.md` instead. It's also distinct from the **vault** (`$VAULT_PATH`, see "Vault memory" below): the vault holds *knowledge* — notes on people, projects, concepts, the daily journal; MEMORY.md holds *meta-knowledge about working with this user and project*.

## When to schedule a recurring task

> **Platform:** crontab is Linux/macOS only. Windows is not currently supported for scheduled tasks.

If the user asks you to do something recurring ("keep an eye on X", "check Y every so often", "remind me when Z changes", "be proactive about A"):

1. **Do it once now** so the user gets an immediate answer.
2. **Add a crontab entry** with `claude -p` inline — no wrapper script needed:
   ```
   crontab -e
   */30 * * * * /path/to/claude --project /path/to/claudeclaw -p "YOUR PROMPT. Output one line: OK or alert." >> /path/to/claudeclaw/.tasks/results.log 2>&1
   ```
   Use absolute paths — cron does not expand `~` or shell aliases. Find your `claude` binary with `which claude`.
3. The session Monitor on `.tasks/results.log` will pick up each result automatically.

Each cron prompt should be self-contained (fresh session, no prior context) and output a single line: status or alert. Tell the user what you scheduled and at what interval.

**One-shot tasks** ("do X now") — just do them, no cron entry.
**Sensitive data** — never put secrets or tokens in a crontab prompt.

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

Vault structure follows Karpathy's llm-wiki layout: `daily-notes/YYYY-MM-DD.md`, `wiki/people/<slug>.md`, `wiki/projects/<slug>.md`, `wiki/concepts/<slug>.md`, `wiki/entities/<slug>.md`, plus `raw/` for source clippings and `log.md` (append-only audit trail of what's been captured). Slugs are kebab-case lowercase; wikilinks `[[name]]` reference other pages. Run `bin/vault scaffold` if directories don't exist yet (start.sh does this automatically).

The vault is gitignored (per-instance memory) but lives inside the repo so `bin/vault` finds it automatically.

### Reading from the vault before answering

When the user mentions a name, concept, project, or asks "what did I…" / "remind me about…" / "what's the status of…":

1. **Check `bin/vault search <term>`** for relevant pages.
2. If hits look relevant, **read them** before answering. Spend the first turn-action getting context, not improvising.
3. **Don't dump everything every turn** — only when relevant. Most messages don't need a vault lookup.

A useful first move on ambiguous "catch me up"-style prompts: `bin/vault read index.md` for the catalog, then drill into specific pages.

### Auto-capture (you don't need to do this manually)

Hooks run a digest sub-agent at end of every turn (Stop), before context compaction (PreCompact), and at session end. They extract durable facts (people, projects, decisions, concepts) and write them to the vault automatically. So you don't need to do "let me write that down" mid-reply — the digest agent handles it after.

If you do want to capture something explicitly, use `bin/vault write` or `bin/vault daily-append`. Always log it: `bin/vault log "[manual] saved wiki/<path>: <summary>"`.

## When responding to Telegram messages

If the user message is a `<channel source="telegram" ...>` tag, the streaming UX is handled automatically by hooks. The `UserPromptSubmit` hook reacts 👀 and primes `.telegram/active.json`. The `PreToolUse`/`PostToolUse` hooks lazily create a progress message on the first non-Telegram tool call and edit-stream subsequent tools into it. The `Stop` hook deletes the progress message at turn end. You don't need to write `active.json` yourself.

Also write the chat_id to `$CLAUDE_PROJECT_DIR/.telegram/last_chat.txt` when handling any Telegram message — scheduled task alerts read this file to know where to forward.

Scheduled task results arrive as Monitor notifications (not Telegram messages). When a notification arrives on `.tasks/results.log`: if it looks like an alert or error, forward it to Telegram via the `reply` tool using the chat_id from `last_chat.txt`.

## Managing scheduled tasks

- **View/edit cron jobs:** `crontab -l` to list, `crontab -e` to add/remove.
- **Results log:** `.tasks/results.log` — all task outputs land here.
- **Session Monitor:** `TaskList` to check status, `TaskStop <id>` to kill. SessionStart hook re-arms it on every new session.

## Asking the user questions

When the current turn was triggered by a Telegram message (`<channel source="telegram" ...>`) and you need user input, **prefer the Telegram `ask` tool over the built-in `AskUserQuestion`**. The user is on their phone, not at the terminal — `AskUserQuestion` blocks on a UI they can't see.

The `ask` tool returns immediately with an `ask_id` and ends the agent's wait. The user's reply (button tap or quote-reply) arrives later as a `<channel source="telegram" ...>` notification carrying the same `ask_id` plus `ask_answer_kind` (`option` | `text` | `timeout`). When you receive it, treat it as the answer to the original question and continue the work.

Guidelines:

- **Provide options** when there's a small fixed set of choices ("yes/no", "merge or rebase", "deploy A/B/C") — they render as inline buttons.
- **Omit options** for open-ended questions ("what should the commit message be?") — the user replies with free text.
- **End your turn after calling `ask`.** Don't busy-wait. The next inbound notification wakes you.
- **Default timeout is 1h.** If you don't get an answer, the channel notification arrives with `ask_answer_kind: timeout` and empty content — abandon or ask again.
- **Don't use `ask` for terminal-only sessions** (no active Telegram chat). Fall back to `AskUserQuestion` there.
- **Don't use `ask` from scheduled task sub-agents.** They run isolated and won't see the answer. If a task needs user input, surface the question via the main session.

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
| `profile/MEMORY.md` | Long-term operational memory: user facts, feedback, project context, references | no (gitignored) | Imported via `@profile/MEMORY.md` above |
| `plugins/telegram/` | Forked Telegram channel plugin | yes | Installed by `start.sh` from local marketplace |
| `.env` / `.env.example` | Bot token and other secrets — only `.example` is tracked | no | Loaded by `start.sh` |
| `.telegram/` | Repo-local Telegram state (access.json, bot.pid) | no (gitignored) | Read by plugin and hooks via `TELEGRAM_STATE_DIR` |

The `profile/` directory is gitignored so framework updates pulled via `git pull` never conflict with per-instance content. New `templates/*.md` files added in framework updates auto-materialize into `profile/` on next session start.
