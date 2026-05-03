# Changelog

All notable changes to claudeclaw will be documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

_(Nothing yet.)_

## [0.1.0] — 2026-05-03

First public release. Establishes the OpenClaw-on-Claude-Code pattern: BOOTSTRAP / IDENTITY / SOUL / USER / HEARTBEAT files driving an always-on agent that talks to Telegram.

### Added

- **One-line install** — `curl -fsSL https://raw.githubusercontent.com/aerolalit/claudeclaw/main/install.sh | bash` clones the repo, drops a `claudeclaw` shim into `~/.local/bin`, and walks the user through auth + bot token + pairing on next launch.
- **`claudeclaw` CLI** with subcommands:
  - `start` (default) — setup + launch (auto-attaches to existing tmux session)
  - `stop` / `restart` — clean lifecycle control
  - `status` — running state, paired senders, last log line
  - `attach` — `tmux attach -t claudeclaw`
  - `logs [-f]` — tail `.telegram/stream.log`
  - `update` — `git pull` + plugin reinstall
  - `doctor` — 19-check diagnostic (deps, auth, plugin, pairing, network)
  - `uninstall [--purge]` — remove shim, optionally delete repo
  - `version` / `help`
- **Forked Telegram channel plugin** (`plugins/telegram/`, Apache-2.0) layered with claudeclaw-specific extensions:
  - **`ask` MCP tool** — non-blocking question-and-wait with inline buttons or free-text reply, returns immediately and resumes via `<channel>` notification when the user answers.
  - **MarkdownV2 reply formatter** (`PreToolUse` hook) — converts standard markdown to Telegram-flavoured MarkdownV2 with proper escaping. Auto-applied to all `reply` calls.
  - **Tool-call streaming** — `PreToolUse`/`PostToolUse` hooks lazily create a Telegram message and edit-stream tool calls into it as the agent works.
  - **👀 reaction on inbound** — visual ack the moment the bot sees your message.
- **Heartbeat loop** — recurring 30-min sub-agent that reads `profile/HEARTBEAT.md` and runs whatever's in it. Filtered out of tool-call streaming so it doesn't spam Telegram.
- **Profile system** — `templates/{IDENTITY,SOUL,USER,HEARTBEAT,BOOTSTRAP}.md` (tracked) auto-copied into `profile/` (gitignored) on first session. CLAUDE.md auto-imports them.
- **Headless auth flow** — interactive `[1] headless` / `[2] desktop` branch in `start.sh`. Headless path walks the user through `claude setup-token` and persists the token to `.env`.
- **tmux integration** — opt-in prompt asking "should this keep running after you close the terminal?" auto-installs tmux via `apt`/`brew`/`dnf`/`pacman`/`apk` if missing, wraps the launch, returns to shell on detach.
- **Vault memory CLI** at `bin/vault` (option A: ripgrep + Karpathy-style `index.md`). Verbs: `search`, `read`, `write`, `daily`, `daily-append`, `backlinks`, `index`, `ls`. Works on a folder of markdown notes (Obsidian-compatible). Configurable via `VAULT_PATH`.
- **Per-instance Telegram state** — bot token, allowlist, bot.pid all live in `<repo>/.telegram/` (gitignored), not `~/.claude/channels/telegram/`. One claudeclaw checkout = one bot, one workspace. Plugin honours `TELEGRAM_STATE_DIR`.
- **`claudeclaw doctor`** — 19 health checks: Node/npm/git/tmux/jq/curl on PATH, Claude Code installed and authenticated, plugin marketplace registered, plugin installed, `.env` populated, allowlist populated, api.telegram.org reachable, tmux session running.
- **CONTRIBUTING.md** — what's in scope, dev setup, code conventions, PR checklist.

### Changed

- `start.sh` is now a multi-subcommand CLI; default behaviour (no args) is unchanged from earlier `./start.sh` invocation.
- README leads with the Claude-subscription positioning and the one-line install. Quickstart is two commands.

### Security

- `.env` and `.telegram/` are gitignored via a strict allowlist `.gitignore` — new files are silently ignored unless explicitly un-ignored.
- Repo-local `.env` is `chmod 600`, `.telegram/` is `chmod 700` after first run.
- claudeclaw runs in `--permission-mode bypassPermissions` by default (documented in README Gotchas). Reasonable for personal use, not what you'd ship to production unaudited.

### Known limitations

- `--dangerously-load-development-channels` shows a TUI confirmation prompt on every Claude Code launch. The flag is required because the forked plugin isn't on Anthropic's official channel allowlist; submission is on the post-v0.1.0 roadmap.
- Telegram stream messages are truncated at 3500 chars (Telegram's hard cap is 4096).
- `bin/vault` ships only the verbs that actually work cleanly. `tag` / `tags` / `project` / `frontmatter` queries deferred to v1.1 (need real YAML parsing, not regex).

[Unreleased]: https://github.com/aerolalit/claudeclaw/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/aerolalit/claudeclaw/releases/tag/v0.1.0
