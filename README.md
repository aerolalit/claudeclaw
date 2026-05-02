# claudeclaw

A Claude Code-native heartbeat workspace. Inspired by [openclaw](https://github.com/openclaw/openclaw), built natively on top of Claude Code's primitives — no daemon, no gateway, just hooks and skills.

What you get:

- **Conversational onboarding.** First time you open the workspace, the agent introduces itself and asks who you are, who *it* is, and how it should communicate. No config files to hand-edit.
- **Persistent identity across sessions.** `IDENTITY.md`, `USER.md`, `SOUL.md` capture who the agent is, who you are, and how it talks. Auto-loaded on every session.
- **Heartbeat loop.** Every 30 minutes, a subagent reads `HEARTBEAT.md` and runs whatever recurring checks live there (inbox triage, deploy status, calendar gaps — whatever you want). Replies `HEARTBEAT_OK` if nothing needs attention.
- **Dual-use template.** This same repo serves as both the published template AND your personal instance. Personal files are gitignored; framework updates pull cleanly without conflicts.

## Get started

```bash
git clone https://github.com/<your>/claudeclaw my-workspace
cd my-workspace
claude
```

Then send any message (e.g. `hi`). The agent will:

1. Auto-copy template files into their personal versions.
2. Read `BOOTSTRAP.md` and start the interview.
3. Fill `IDENTITY.md` / `USER.md` / `SOUL.md` from your conversation.
4. Optionally seed `HEARTBEAT.md` with recurring checks you want.
5. Delete `BOOTSTRAP.md` to mark setup complete.
6. Arm the heartbeat loop (every 30 min while the session is open).

Subsequent sessions skip the interview and go straight to normal operation, with the heartbeat re-armed automatically.

## File layout

| File | Tracked? | What it is |
|------|----------|------------|
| `CLAUDE.md` | yes | Framework instructions Claude Code reads on session start |
| `.claude/settings.json` | yes | Permissions + 2 SessionStart hooks (auto-copy + heartbeat-bootstrap) |
| `*.example` | yes | Template versions of personal files |
| `BOOTSTRAP.md` | no | First-run interview script (deleted after onboarding) |
| `IDENTITY.md` | no | Agent's name, vibe, emoji |
| `USER.md` | no | What the agent knows about you |
| `SOUL.md` | no | The agent's voice, stance, communication style |
| `HEARTBEAT.md` | no | Recurring checks the heartbeat agent runs |

## Pulling framework updates

```bash
git pull
```

`git pull` only touches tracked files (CLAUDE.md, settings.json, `*.example`, etc.) — your personal files stay put. If a new `*.example` file shows up in the update, the SessionStart auto-copy hook materializes it on the next session start (so when you later add e.g. `TOOLS.md.example` to the framework, existing users get a populated `TOOLS.md` automatically).

## Reset onboarding

To re-run the interview from scratch:

```bash
rm IDENTITY.md USER.md SOUL.md HEARTBEAT.md
cp BOOTSTRAP.md.example BOOTSTRAP.md
```

Next session start, the auto-copy hook restores the personal files from `.example`, BOOTSTRAP.md triggers the interview again.

## Stopping the heartbeat

Tell the agent "stop the heartbeat" — it'll cancel the active cron job. The loop is session-only (in-memory cron); it dies when Claude Code closes regardless.

## Telegram (optional)

Talk to your workspace from Telegram, and let the agent push you alerts (e.g. heartbeat findings) back. Uses Anthropic's [official Telegram channel plugin](https://github.com/anthropics/claude-plugins-official/tree/main/external_plugins/telegram). Bidirectional, session-only — when you close Claude Code, the bridge stops.

### Requirements

- Claude Code **v2.1.80+**
- Logged in via `claude.ai` (Console / API key auth is not supported)
- [Bun](https://bun.sh) runtime: `curl -fsSL https://bun.sh/install | bash`
- A Telegram account

### One-time setup

1. **Create a bot.** Open Telegram, message [@BotFather](https://t.me/BotFather), send `/newbot`, follow the prompts. You'll get a token like `123456789:AAH...`. Copy it.
2. **Install the plugin** in any Claude Code session:
   ```
   /plugin install telegram@claude-plugins-official
   /reload-plugins
   ```
3. **Save the token:**
   ```
   /telegram:configure 123456789:AAH...
   ```
   The token is stored in `~/.claude/channels/telegram/.env` (chmod 600).
4. **Restart Claude with the channel active:**
   ```
   claude --channels plugin:telegram@claude-plugins-official
   ```
5. **Pair your Telegram account.** DM your bot anything — it replies with a 6-character pairing code. In Claude:
   ```
   /telegram:access pair <code>
   ```
6. **Lock down access** so only paired users can talk to your workspace:
   ```
   /telegram:access policy allowlist
   ```

Done. Now any Telegram message from your account lands in the active session as a user turn, and Claude's replies route back to Telegram.

### Using it day-to-day

Every session where you want Telegram active, launch with the `--channels` flag:

```bash
claude --channels plugin:telegram@claude-plugins-official
```

If you forget the flag, the plugin's tools still load but no inbound messages flow. (A shell alias makes this less painful — see `.scratch/start.sh` for examples.)

### Useful commands inside Claude

| Command | What it does |
|---------|--------------|
| `/telegram:configure` | Show current token / bot status |
| `/telegram:configure clear` | Delete the stored token |
| `/telegram:access` | Show current allowlist and policy |
| `/telegram:access pair <code>` | Pair a new Telegram user via code |
| `/telegram:access allow <senderId>` | Manually allowlist a user ID |
| `/telegram:access remove <senderId>` | Remove a user from the allowlist |
| `/telegram:access policy <pairing\|allowlist\|disabled>` | Switch enforcement mode |

### Gotchas

- **One session at a time.** If you have stale Claude processes still polling, you'll get message loss. Run `pkill -f "bun.*telegram"` before starting if things go quiet.
- **Silent failure.** No connection-status indicator. If messages stop arriving, restart Claude.
- **Don't commit the token.** It lives in `~/.claude/channels/telegram/.env`, never in this repo. Don't paste it into HEARTBEAT.md or CLAUDE.md — those go into the prompt every tick.
- **Team / Enterprise users:** your admin must set `channelsEnabled: true` in managed settings before any of this works.

### Extending Telegram behavior

You usually don't need to touch the plugin itself. To customize:

- **Reply style / tone:** add to SOUL.md (e.g. "Telegram replies should be one paragraph max").
- **Quiet hours:** add to SOUL.md (e.g. "Don't reply via Telegram between 22:00–07:00 unless message includes 'URGENT'").
- **Per-sender behavior:** add to USER.md as you learn.
- **Cross-cutting filters** (e.g. strip secrets, append signature): use a `PreToolUse` hook on the Telegram `reply` tool in `.claude/settings.json`.

Only fork or replace the plugin if you need new channel mechanics (webhooks instead of polling, attachments, etc.) — see the [plugin source](https://github.com/anthropics/claude-plugins-official/tree/main/external_plugins/telegram).

## How it works (brief)

- **`SessionStart` hook (auto-copy)** — runs first on every session start/resume. For each `*.example` file, copies it to its real name only if the real file doesn't exist. Idempotent.
- **`SessionStart` hook (heartbeat-bootstrap)** — runs second. Injects context telling the agent to invoke the `loop` skill with a 30-minute prompt that delegates the actual heartbeat work to a subagent (keeps main context clean).
- **`CLAUDE.md`** — auto-loaded on session start. Imports IDENTITY/USER/SOUL/HEARTBEAT via `@filename` syntax. Tells the agent to run BOOTSTRAP.md if it exists.
- **`.gitignore`** — separates framework (tracked) from personal data (gitignored) so `git pull` is always conflict-free on user content.

## Credit

Heavily inspired by [openclaw](https://github.com/openclaw/openclaw)'s BOOTSTRAP / IDENTITY / SOUL / USER / HEARTBEAT model. This is that pattern reimplemented natively on Claude Code, without the openclaw gateway/daemon — just files, hooks, and the `loop` skill.
