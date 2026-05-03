# claudeclaw

A personality, heartbeat loop, and Telegram bridge for [Claude Code](https://docs.anthropic.com/claude-code) — bring your subscription, skip the API key.

claudeclaw is a workspace template for people who already pay for Claude (Pro/Max/Team) and want their CLI to feel like an always-on co-worker: it knows who you are, talks the way you've trained it to, runs recurring background checks, and answers your phone over Telegram. All of it routed through your existing Claude Code session — no separate daemon, no extra LLM API key.

If you've used [OpenClaw](https://github.com/openclaw/openclaw) and liked the model but didn't want to pay twice for inference, this is that pattern reimplemented on Claude Code's primitives (hooks, skills, channel plugins).

## What you get

- **Conversational onboarding.** First launch, the agent asks who you are, who *it* is, how it should communicate. No config files to hand-edit.
- **Persistent identity across sessions.** `profile/IDENTITY.md`, `USER.md`, `SOUL.md` capture the agent, you, and the voice. Auto-loaded every session.
- **Heartbeat loop.** Every 30 minutes a sub-agent reads `profile/HEARTBEAT.md` and runs whatever recurring checks live there — inbox triage, deploy status, AI news, calendar gaps. Replies `HEARTBEAT_OK` if nothing needs attention.
- **Telegram bridge.** Talk to your workspace from your phone. The agent reacts 👀 on inbound, streams tool calls live as it works, and pushes the final reply with a notification. Telegram-flavoured Markdown is rendered automatically.
- **Shippable as a template.** This same repo is both the published template AND your personal instance. Personal files live under `profile/` (gitignored); framework updates pull cleanly with no merge conflicts.

## Requirements

- [Claude Code](https://docs.anthropic.com/claude-code) v2.1.80 or later, logged in via claude.ai (Pro / Max / Team — not Console / API key)
- Node.js 18+ and npm (for the Telegram plugin)
- A Telegram account if you want the phone bridge

## Quickstart

```bash
git clone https://github.com/aerolalit/claudeclaw my-workspace
cd my-workspace
./start.sh
```

`start.sh` does everything on first run:

1. Installs the Telegram plugin's npm dependencies.
2. Registers the local `claudeclaw` plugin marketplace with Claude Code.
3. Installs the bundled Telegram plugin from that marketplace.
4. Prompts you for a Telegram bot token (get one from [@BotFather](https://t.me/BotFather) → `/newbot`) and saves it to a gitignored `.env`.
5. Spins up the bot, asks you to DM it once, captures the pairing code from your reply, and writes you to the allowlist.
6. Launches Claude Code with the channel active.

Then send any message in Claude (e.g. `hi`). The interview kicks in, you answer a few questions, and the workspace is ready.

Subsequent runs skip every setup step — straight to launch.

To launch without the Telegram bridge: `./start.sh --no-tg`.

## File layout

```
claudeclaw/
├── CLAUDE.md                ← framework instructions Claude Code reads on session start
├── start.sh                 ← one-command bootstrap + launch
├── README.md / LICENSE
├── .env / .env.example      ← bot token (gitignored / template)
│
├── templates/               ← TRACKED: per-instance file templates
│   ├── BOOTSTRAP.md         ← first-run interview script
│   ├── IDENTITY.md          ← who the agent is
│   ├── SOUL.md              ← how the agent talks
│   ├── USER.md              ← who you are
│   └── HEARTBEAT.md         ← recurring checks for the heartbeat loop
│
├── profile/                 ← GITIGNORED: live per-instance files (auto-copied from templates/)
│
├── .claude/
│   ├── settings.json        ← permissions + hooks
│   └── hooks/               ← Telegram streaming + reply formatting + lifecycle
│
├── .claude-plugin/
│   └── marketplace.json     ← declares the local "claudeclaw" plugin marketplace
│
├── plugins/
│   └── telegram/            ← forked Telegram channel plugin (Apache-2.0)
│
└── .telegram/               ← GITIGNORED: per-instance Telegram state (access.json, bot.pid)
```

## How it works

- **`SessionStart` hook (auto-copy):** copies any new templates from `templates/` into `profile/` if missing. Existing files aren't overwritten.
- **`SessionStart` hook (heartbeat bootstrap):** injects context telling the agent to arm a 30-minute `loop` skill that delegates each tick to a sub-agent — keeping main context clean.
- **`UserPromptSubmit` hook:** on inbound Telegram messages, reacts 👀 and primes `.telegram/active.json`.
- **`PreToolUse` / `PostToolUse` hooks:** lazily create a Telegram progress message on the first non-Telegram tool call and edit-stream subsequent tools into it.
- **`PreToolUse` (scoped to `reply`):** transforms standard markdown into Telegram MarkdownV2 (escapes specials, converts `**bold**` and bullet markers correctly) so replies render cleanly.
- **`Stop` / `SessionEnd` hooks:** delete the streamed progress message at end of turn / clean up state on exit.
- **`CLAUDE.md`:** auto-loaded each session. Imports the live profile files via `@profile/IDENTITY.md` etc. Tells the agent to run `profile/BOOTSTRAP.md` if it exists.
- **`.gitignore`:** strict allowlist — only files you've explicitly tracked are visible to git. New files are silently ignored until you add a `!` rule for them.

## Pulling framework updates

```bash
git pull
```

`profile/` is gitignored, so personal content never conflicts with upstream changes. New `templates/*.md` files added in the framework auto-materialize into `profile/` on next session start.

## Reset onboarding

To re-run the interview:

```bash
rm profile/IDENTITY.md profile/USER.md profile/SOUL.md profile/HEARTBEAT.md
cp templates/BOOTSTRAP.md profile/BOOTSTRAP.md
```

Next session, the auto-copy hook restores the personal files from templates and `BOOTSTRAP.md` triggers a fresh interview.

## Customising Telegram behaviour

Most things live in `profile/SOUL.md`:

- **Reply tone / brevity:** "Telegram replies should be one paragraph max."
- **Quiet hours:** "Don't reply via Telegram between 22:00–07:00 unless message contains 'URGENT'."

Per-user behaviour belongs in `profile/USER.md`. Cross-cutting filters (strip secrets, append signature, etc.) belong as `PreToolUse` hooks on `mcp__plugin_telegram_telegram__reply` in `.claude/settings.json` — the existing `telegram-reply-format.sh` is the model.

## Running on a server (Pi, VPS, etc.)

Claude Code is interactive — it must be attached to a TTY. To keep claudeclaw running after you close the SSH session, wrap it in `tmux` on the server:

```bash
# install tmux once: sudo apt install -y tmux  (Linux)  or  brew install tmux  (Mac)

ssh user@server
tmux new -s claudeclaw 'cd ~/claudeclaw && ./start.sh'
# the dev-channels prompt appears once — press Enter to confirm
# then detach with: Ctrl+B then D
# now back in your shell; close terminal — Claude keeps running

# tomorrow:
ssh user@server
tmux attach -t claudeclaw
```

The dev-channels confirmation prompt fires every time `claude --dangerously-load-development-channels` is launched (Anthropic gates it deliberately while the channel system is in research preview). Inside tmux it's a one-time annoyance — Claude stays running, you only see the prompt on the first launch and after each restart.

For boot-time autostart, add a systemd user service (Linux) or launchd plist (macOS) that runs `tmux new-session -d -s claudeclaw 'cd ~/claudeclaw && ./start.sh'` on login.

## Stopping the heartbeat

Tell the agent "stop the heartbeat" in any session — it cancels the cron job. The loop is session-only (in-memory cron); it dies when Claude Code exits regardless.

## Gotchas

- **One Telegram session at a time per bot token.** If you have a stale Claude process still polling, restart cleanly with `pkill -f "claude --dangerously" && ./start.sh`.
- **Forked plugins are off the official channel allowlist** during the research preview. `start.sh` uses `--dangerously-load-development-channels` to bypass — fine for personal/team use, not what you'd use for a production deployment without a security review.
- **Don't commit `.env` or `.telegram/`.** They're gitignored, but double-check after large refactors.
- **Team / Enterprise users:** your admin must enable `channelsEnabled: true` in managed settings.

## License

claudeclaw is **MIT licensed** (see `LICENSE`).

The bundled Telegram plugin in `plugins/telegram/` is a fork of [`telegram@claude-plugins-official`](https://github.com/anthropics/claude-plugins-official/tree/main/external_plugins/telegram) and remains under the **Apache License 2.0** (see `plugins/telegram/LICENSE` and `plugins/telegram/NOTICE`).

## Credit

The conceptual model — BOOTSTRAP / IDENTITY / SOUL / USER / HEARTBEAT, conversational onboarding, profile-as-prompt — is borrowed from [OpenClaw](https://github.com/openclaw/openclaw). claudeclaw is that pattern, on Claude Code.
