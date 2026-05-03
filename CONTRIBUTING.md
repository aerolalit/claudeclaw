# Contributing to claudeclaw

Thanks for considering a contribution. claudeclaw is small enough that one person can read the whole codebase in an afternoon — that's a feature. PRs that keep it that way are welcome.

## What's in scope

Things this project genuinely wants:

- **Bug fixes** in `start.sh`, `install.sh`, the Telegram plugin fork (`plugins/telegram/`), or the hook scripts (`.claude/hooks/`).
- **Cross-platform support.** Linux, macOS, and WSL are all real targets. Windows-native isn't.
- **Subcommands** for `claudeclaw` (e.g. better `doctor` checks, more granular `status`, additional lifecycle verbs).
- **Documentation improvements** — the troubleshooting section especially. If you hit a failure that's not covered, that's a missed teaching moment.
- **New channel plugins** layered on the same hook + skill scaffolding (Discord, iMessage, Slack…). The Telegram fork is the template.
- **Extending the memory CLI** at `bin/vault` — backlinks, search, frontmatter queries. See [the v1.1 roadmap in the file header](bin/vault).

Things this project doesn't want:

- New top-level features that aren't user-driven.
- Heavy abstractions ("plugin system for hooks", "DI for skills"). The point is that 250 lines of bash is enough.
- Replacing tested working code with "cleaner" rewrites.
- Anything that breaks the "clone and run" UX.

## Local development

You'll need: Node 18+, npm, git, jq, tmux. The installer script auto-installs them on supported package managers — for development just have them on your PATH.

```bash
git clone https://github.com/aerolalit/claudeclaw ~/claudeclaw-dev
cd ~/claudeclaw-dev

# install plugin deps once
cd plugins/telegram && npm install && cd ../..

# don't run install.sh — it would install a system-wide claudeclaw shim
# pointing at this checkout. Instead, run start.sh directly:
./start.sh
```

When testing changes to `plugins/telegram/server.ts`, your local edits won't take effect until Claude Code reinstalls the plugin from the marketplace. Use:

```bash
claudeclaw update
# or manually:
claude plugin marketplace update claudeclaw
claude plugin uninstall telegram@claudeclaw
echo y | claude plugin install telegram@claudeclaw --scope project
claudeclaw restart
```

## Code conventions

- **Bash** for `start.sh`, `install.sh`, hook scripts. POSIX-portable where possible (some Linux-isms are unavoidable; gracefully degrade on macOS).
- **TypeScript** for the Telegram plugin (`plugins/telegram/`). Strict mode. No build step — runs through `tsx`.
- **Hook scripts must fail silently** to `.telegram/stream.log`. A buggy hook should never block a Claude session.
- **No assumed PATH.** Non-interactive shells (cron, ssh -c, hooks) don't source `.bashrc`. Use full paths or prepend known dirs explicitly.
- **Comment intent, not mechanism.** Why a check exists, not what `[ -f x ]` does.

## Before opening a PR

1. `claudeclaw doctor` passes 19/19 on your machine.
2. Manual smoke test: `claudeclaw stop && claudeclaw start` works end-to-end.
3. If you touched `start.sh`: run `bash -n start.sh` to catch syntax errors before pushing.
4. If you touched hooks: send a message in your real Telegram chat and confirm streaming + reply formatting still work.
5. New user-visible behaviour gets a one-line entry in `CHANGELOG.md` under `[Unreleased]`.

There are no automated tests yet. Adding a real test harness is itself a welcome PR.

## Forking the Telegram plugin

`plugins/telegram/` is a fork of [`telegram@claude-plugins-official`](https://github.com/anthropics/claude-plugins-official/tree/main/external_plugins/telegram), Apache 2.0. Modifications must:

- Keep `plugins/telegram/LICENSE` and `plugins/telegram/NOTICE` intact (Apache §4(d)).
- Note significant edits in `plugins/telegram/NOTICE` or the commit message.
- Stay compatible with the upstream channel protocol — we want users to be able to swap our fork for upstream if Anthropic adds whatever feature we built.

## Commit messages

Imperative mood, what changed and why. Example:

```
start.sh: resolve symlinks when computing REPO_ROOT

When invoked through ~/.local/bin/claudeclaw, dirname "$0" returned the
symlink's dir so REPO_ROOT became ~/.local/bin and `cd plugins/telegram`
failed. Resolve $0 through any symlinks first using a POSIX-portable
readlink loop.
```

Skip the boilerplate "this commit", "I added", etc. Co-author trailers for tools that helped are fine.

## Reporting issues

`claudeclaw doctor`, `claudeclaw version`, last 30 lines of `claudeclaw logs`, what you ran, what happened. Without those, an issue is unactionable.

## Maintainer

[@aerolalit](https://github.com/aerolalit). Response time is "when I get to it" — this is a side project. Patience appreciated.
