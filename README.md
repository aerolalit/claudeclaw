# claudeclaw

A personality, scheduled task system, and Telegram bridge for [Claude Code](https://docs.anthropic.com/claude-code) — bring your subscription, skip the API key.

claudeclaw is a workspace template for people who already pay for Claude (Pro/Max/Team) and want their CLI to feel like an always-on co-worker: it knows who you are, talks the way you've trained it to, runs recurring background checks, and answers your phone over Telegram. All of it routed through your existing Claude Code session — no separate daemon, no extra LLM API key.

If you've used [OpenClaw](https://github.com/openclaw/openclaw) and liked the model but didn't want to pay twice for inference, this is that pattern reimplemented on Claude Code's primitives (hooks, skills, channel plugins).

![claudeclaw demo](assets/demo.gif)

## Not affected by the June 15, 2026 Agent SDK pricing change

Anthropic's [June 15 change](https://support.anthropic.com/) moves **programmatic usage** — the Claude Agent SDK and `claude -p` (headless/print mode) — onto a separate metered budget that draws on extra usage at API rates once a monthly credit is spent. Tools built on `claude -p` or the Agent SDK are affected by this.

**claudeclaw is not.** It drives an **interactive Claude Code session** — the same session you'd run by typing `claude` in a terminal — not the Agent SDK. The Telegram bridge and hooks operate inside that one interactive session. Scheduled tasks use OS cron + `claude -p` (which does count toward the separate budget), but the main session itself stays on your subscription. Anthropic's announcement is explicit that **interactive usage of Claude Code stays on your normal subscription limits, unchanged.**

In practical terms: if you're on Pro / Max / Team, claudeclaw keeps running off your existing subscription after June 15 with no API billing and no need to claim the separate Agent SDK credit. Nothing here changes for you.

## What you get

- **Conversational onboarding.** First launch, the agent asks who you are, who *it* is, how it should communicate. No config files to hand-edit.
- **Persistent identity across sessions.** `profile/IDENTITY.md`, `USER.md`, `SOUL.md` capture the agent, you, and the voice. Auto-loaded every session.
- **Scheduled tasks.** Add any recurring check to the system crontab as a one-line `claude -p` entry. Results append to `.tasks/results.log`; the session watches that file via a persistent Monitor and surfaces alerts interactively so you can discuss them.
- **Telegram bridge.** Talk to your workspace from your phone. The agent reacts 👀 on inbound, streams tool calls live as it works, and pushes the final reply with a notification. Telegram-flavoured Markdown is rendered automatically.
- **Shippable as a template.** This same repo is both the published template AND your personal instance. Personal files live under `profile/` (gitignored); framework updates pull cleanly with no merge conflicts.

## Requirements

- [Claude Code](https://docs.anthropic.com/claude-code) v2.1.80 or later, logged in via claude.ai (Pro / Max / Team — not Console / API key). claudeclaw runs as an **interactive** session, so it stays on your subscription limits and is unaffected by the June 15, 2026 Agent SDK pricing change (see above).
- Node.js 18+ and npm (for the Telegram plugin)
- A Telegram account if you want the phone bridge

## Quickstart

One line:

```bash
curl -fsSL https://raw.githubusercontent.com/aerolalit/claudeclaw/latest/install.sh | bash
```

This installs prereqs (git, node) if missing, clones the repo to `~/claudeclaw`, drops a `claudeclaw` shim into `~/.local/bin`, and tells you to run `claudeclaw` for setup.

The `latest` tag tracks the most recent release. To pin to a specific version (e.g. for reproducible installs across machines), swap `latest` for a version tag like `v0.1.0`. To install elsewhere: `CLAUDECLAW_DIR=/custom/path curl -fsSL ... | bash`.

Or do it manually:

```bash
git clone https://github.com/aerolalit/claudeclaw ~/claudeclaw
cd ~/claudeclaw
./start.sh
```

`claudeclaw` (or `./start.sh`) does everything else on first run:

1. Installs Claude Code if missing (`claude.ai/install.sh`).
2. Walks you through auth — interactive paste of a setup-token for headless servers, or `claude login` on desktop.
3. Installs the Telegram plugin's npm dependencies.
4. Registers the local `claudeclaw` plugin marketplace with Claude Code.
5. Installs the bundled Telegram plugin from that marketplace.
6. Prompts for a Telegram bot token (get one from [@BotFather](https://t.me/BotFather) → `/newbot`) and saves it to a gitignored `.env`.
7. Spins up the bot, asks you to DM it once, captures the pairing code from your reply, and writes you to the allowlist.
8. Offers to wrap the launch in tmux so it survives terminal close (default yes).
9. Launches Claude Code with the channel active.

Then send any message in Claude (e.g. `hi`). The interview kicks in, you answer a few questions, and the workspace is ready.

Subsequent runs skip every setup step — straight to launch (or reattach to an existing tmux session).

Daily use: `claudeclaw` (start or attach), `claudeclaw status`, `claudeclaw stop`, `claudeclaw logs`, `claudeclaw update`, `claudeclaw doctor`. See `claudeclaw help` for everything.

To launch without the Telegram bridge: `claudeclaw --no-tg`.

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
- **`SessionStart` hook (task monitor bootstrap):** injects context telling the agent to arm a persistent `Monitor` on `.tasks/results.log` — results from OS cron jobs land in session context automatically.
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
rm profile/IDENTITY.md profile/USER.md profile/SOUL.md
cp templates/BOOTSTRAP.md profile/BOOTSTRAP.md
```

Next session, the auto-copy hook restores the personal files from templates and `BOOTSTRAP.md` triggers a fresh interview.

## Customising Telegram behaviour

Most things live in `profile/SOUL.md`:

- **Reply tone / brevity:** "Telegram replies should be one paragraph max."
- **Quiet hours:** "Don't reply via Telegram between 22:00–07:00 unless message contains 'URGENT'."

Per-user behaviour belongs in `profile/USER.md`. Cross-cutting filters (strip secrets, append signature, etc.) belong as `PreToolUse` hooks on `mcp__plugin_telegram_telegram__reply` in `.claude/settings.json` — the existing `telegram-reply-format.sh` is the model.

## Running on a server (Pi, VPS, etc.)

Claude Code is interactive — it must be attached to a TTY. claudeclaw handles this for you with `tmux`: on first run it asks "should this keep running after you close the terminal?" and if yes, wraps the launch in a tmux session named `claudeclaw`.

Typical flow:

```bash
ssh user@server
claudeclaw                  # first time: setup + launches inside tmux
                            # subsequent: detects existing session, asks to reattach
# detach: Ctrl+B then D
# close terminal — Claude keeps running on the server

# tomorrow:
ssh user@server
claudeclaw attach           # reconnects to the running session
```

The dev-channels confirmation prompt fires every time `claude --dangerously-load-development-channels` is launched (Anthropic gates it deliberately while the channel system is in research preview). Inside tmux it's a one-time annoyance — Claude stays running, you only see the prompt on the first launch and after each restart.

For boot-time autostart, add a systemd user service (Linux) or launchd plist (macOS) that runs `tmux new-session -d -s claudeclaw 'claudeclaw'` on login.

## Managing scheduled tasks

View cron jobs: `crontab -l`. Add/remove: `crontab -e`. Results land in `.tasks/results.log` and are picked up by the session Monitor automatically. The Monitor is re-armed on every session start — no manual setup needed after adding a new cron entry.

## Gotchas

- **One Telegram session at a time per bot token.** If you have a stale Claude process still polling, restart cleanly with `claudeclaw restart`.
- **Forked plugins are off the official channel allowlist** during the research preview. `start.sh` uses `--dangerously-load-development-channels` to bypass — fine for personal/team use, not what you'd use for a production deployment without a security review.
- **Don't commit `.env` or `.telegram/`.** They're gitignored, but double-check after large refactors.
- **Team / Enterprise users:** your admin must enable `channelsEnabled: true` in managed settings.

## Troubleshooting

Always start with:

```bash
claudeclaw doctor
```

It walks 19 health checks covering deps, Claude Code auth, plugin install, Telegram pairing, network reachability, and runtime state. The failing line tells you what's broken. Below are the most common failures and their fixes.

### "claude: command not found" after install

`~/.local/bin` isn't on your shell's PATH. The installer prints the exact line to add to your `~/.bashrc` / `~/.zshrc`. After adding it, `source ~/.bashrc` or open a new terminal.

### "Claude Code is installed but not authenticated"

Two valid auth paths:

- **Desktop with browser:** run `claude login`.
- **Server / Pi (no browser):** on a desktop machine, run `claude setup-token` and paste the token into `claudeclaw`'s `.env`:

  ```bash
  echo 'CLAUDE_CODE_OAUTH_TOKEN=<your-token>' >> ~/claudeclaw/.env
  ```

  `start.sh` walks you through this interactively if you re-run it.

### Bot doesn't respond on Telegram

1. `claudeclaw status` — is the tmux session running?
2. `claudeclaw logs -f` — anything in the stream log?
3. **Token revoked or wrong?** Reset via `@BotFather` → `/revoke` → paste new token into `.env`.
4. **Pairing missing?** `cat .telegram/access.json` — is your `chat_id` in `allowFrom`? If not, re-run pairing: `claudeclaw stop && rm .telegram/access.json && claudeclaw start`.
5. **Two bots polling the same token.** Telegram only allows one. Kill any leftover Claude processes: `pkill -f "claude --dangerously"`.

### "Plugin not installed" on launch

```bash
claudeclaw stop
cd ~/claudeclaw
claude plugin marketplace remove claudeclaw 2>/dev/null
claude plugin uninstall telegram@claudeclaw --scope project 2>/dev/null
claudeclaw start
```

### tmux session is stuck / Claude crashed inside it

```bash
claudeclaw restart
```

If `claudeclaw status` shows the session running but you can't get output: `tmux kill-session -t claudeclaw && claudeclaw start`.

### Markdown isn't rendering in Telegram replies

Inspect `.claude/hooks/telegram-reply-format.sh` — that's the formatter. Run a smoke test:

```bash
echo '{"tool_name":"mcp__plugin_telegram_telegram__reply","tool_input":{"chat_id":"123","text":"# Hi\n- one\n- two"}}' \
  | bash .claude/hooks/telegram-reply-format.sh \
  | jq -r '.hookSpecificOutput.updatedInput.text'
```

If the output looks wrong, the hook has the bug. If it looks right, Telegram is rendering it but you're missing `format: "markdownv2"` (the hook auto-sets this — check it isn't being stripped elsewhere).

### Hooks aren't firing

The hooks live in `.claude/hooks/`. They're triggered by `.claude/settings.json` events. Check:

```bash
cat .claude/settings.json | jq '.hooks'      # are the events registered?
ls -la .claude/hooks/                         # files executable (chmod +x)?
tail -f .telegram/stream.log                  # any silent failures logged?
```

Hooks fail silently to `stream.log` by design (so a hook bug doesn't kill your session). Always check that file when something feels off.

### "session 'claudeclaw' already exists" when starting

Either you have a leftover tmux session (`tmux kill-session -t claudeclaw`) or you're inside an outer tmux already (`echo $TMUX` will show a non-empty path). Detach the outer one or run `claudeclaw start` from a non-tmux shell.

### Re-pairing without losing token

```bash
claudeclaw stop
rm .telegram/access.json
claudeclaw start
```

Only `access.json` (sender allowlist) gets reset. Bot token in `.env` stays.

### Update broke something — how do I roll back?

```bash
cd ~/claudeclaw
git log --oneline | head -5     # find a good commit
git checkout <commit-sha>
claudeclaw restart
```

Or wipe and reinstall: `claudeclaw uninstall --purge && curl -fsSL https://raw.githubusercontent.com/aerolalit/claudeclaw/main/install.sh | bash`.

### Still stuck

Open an issue at <https://github.com/aerolalit/claudeclaw/issues> with:

- `claudeclaw doctor` output
- `claudeclaw version` output
- Last 30 lines of `claudeclaw logs`
- What you ran and what you expected to happen.

## Security & trust model

A few things worth knowing once you're set up — none of these are red flags, just good context:

- **The Telegram chat is effectively a remote terminal.** Anyone you pair (on the `allowFrom` allowlist) can send messages that get executed with your local privileges. claudeclaw runs in `bypassPermissions` mode by default so the agent doesn't ask before each command — that's the whole UX. Pair only with accounts you fully trust.
- **Your bot token is a credential.** It's stored in `.env` (chmod 600, gitignored). If it ever leaks, revoke immediately via `@BotFather` → `/revoke`.
- **Your Claude Code auth token is also a credential.** `CLAUDE_CODE_OAUTH_TOKEN` in the same `.env` grants access to your claude.ai subscription. Same care applies.
- **Hooks can run arbitrary shell.** `.claude/hooks/*.sh` execute on every tool call. Review them on first install and after any `git pull`. They're under 100 lines each — fast to audit.
- **Prompt injection is real.** A webpage or file the agent reads can contain instructions that the agent then executes. With `bypassPermissions` on, there's no human-in-the-loop check. Don't point claudeclaw at untrusted inputs without thinking.

For the full threat model, hardening recipes (deny rules, dropping bypass mode, dedicated user accounts, encrypting `.env` at rest), and how to report vulnerabilities, see **[SECURITY.md](SECURITY.md)**.

## License

claudeclaw is **MIT licensed** (see `LICENSE`).

The bundled Telegram plugin in `plugins/telegram/` is a fork of [`telegram@claude-plugins-official`](https://github.com/anthropics/claude-plugins-official/tree/main/external_plugins/telegram) and remains under the **Apache License 2.0** (see `plugins/telegram/LICENSE` and `plugins/telegram/NOTICE`).

## Credit

The conceptual model — BOOTSTRAP / IDENTITY / SOUL / USER, conversational onboarding, profile-as-prompt — is borrowed from [OpenClaw](https://github.com/openclaw/openclaw). claudeclaw is that pattern, on Claude Code.
