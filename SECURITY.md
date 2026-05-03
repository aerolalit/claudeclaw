# Security Policy

## Reporting a vulnerability

**Please do not file public GitHub issues for security vulnerabilities.**

Email the maintainer directly: **aerolalit@gmail.com**.

I'll respond within a few days. After we've discussed and patched the issue, we'll coordinate a public disclosure (typically a CHANGELOG entry and a CVE if one applies).

## Threat model — what claudeclaw protects against, and what it doesn't

### What it does protect

- **Telegram inbound is gated** by a per-instance allowlist (`.telegram/access.json`). Messages from unpaired senders are silently dropped.
- **Per-instance state.** `.env`, `.telegram/access.json`, bot.pid, etc. live inside the cloned repo, not under `~/.claude/`. One claudeclaw checkout = one bot, one allowlist. No cross-contamination between repos.
- **`.gitignore` is strict-allowlist mode.** New files are silently ignored unless explicitly un-ignored. Reduces accidental token / state commits.
- **`.env` is `chmod 600`, `.telegram/` is `chmod 700`.** Other users on the same machine can't read your bot token or pairing data.
- **Tokens never echo to the terminal during paste prompts** (`read -rs`). No scrollback / session-log leakage during setup.
- **Forked plugin runs locally.** No third-party code is fetched at runtime; everything is auditable in `plugins/telegram/`.

### What it does NOT protect against

- **Running with `bypassPermissions`.** This is the default. Anyone who can send a Telegram message to the agent — i.e. anyone on your `allowFrom` allowlist — can ask the agent to run arbitrary shell commands. **The Telegram conversation IS a remote shell to the host running claudeclaw.** Read that twice. Pair only with accounts you fully trust.
- **Prompt injection.** If the agent reads a webpage, file, or third-party output containing instructions, those instructions are executed by the agent with full bypass permissions. Malicious URLs in your daily notes, fake email summaries, log files an attacker controls — all attack surface.
- **Compromised Anthropic auth token.** Your `CLAUDE_CODE_OAUTH_TOKEN` is valid for ~1 year and grants full claude.ai account access. If `.env` leaks, your account does too. Rotate via `claude setup-token` on a clean machine if you suspect compromise.
- **Compromised Telegram bot token.** With your bot token, an attacker can impersonate your bot, read all DMs sent to it, and reply as it. The pairing allowlist is enforced inside claudeclaw's plugin — an attacker bypassing the plugin (e.g. by polling Telegram directly with the leaked token) doesn't trigger the gate. **Revoke immediately** via `@BotFather` → `/revoke` if the token leaks.
- **Multi-user systems.** claudeclaw assumes a single-user host. The repo is `chmod 755` (world-readable structure), even though sensitive files inside are not. Don't run on a shared server with untrusted other users.
- **Supply chain on `main`.** The one-line installer pulls `install.sh` from `main`. If `main` is compromised (force push, account takeover), every user pulling that day pulls malicious code. We pin example commands in CHANGELOG to specific tags. For maximum paranoia, install from a specific tag URL: `curl ... /v0.1.0/install.sh | bash`.

## Hardening guide

If you care about defense-in-depth:

### 1. Drop bypass permissions

The default is `bypassPermissions`. To require approval for destructive operations, edit `.claude/settings.json` and remove the `--permission-mode bypassPermissions` flag from `start.sh`'s launch line, or change to `acceptEdits` (auto-approves Edit/Write only, prompts on Bash/Agent).

The cost: every Bash tool call asks for approval. The benefit: a prompt injection can't `rm -rf ~` without you tapping yes.

### 2. Restrict what the agent can do

Add `permissions.deny` rules in `.claude/settings.json`:

```json
"permissions": {
  "deny": [
    "Bash(rm -rf *)",
    "Bash(curl * | bash *)",
    "Bash(curl * | sh *)",
    "Bash(git push --force *)",
    "Bash(git reset --hard *)",
    "Edit(/etc/**)",
    "Edit(~/.ssh/**)",
    "Read(~/.aws/**)",
    "Read(~/.gnupg/**)"
  ]
}
```

These work even with `bypassPermissions` — deny rules are checked before the bypass.

### 3. Run on a dedicated user account

If you're hosting on a server, create a `claudeclaw` system user. Limit its file access to just what claudeclaw needs. If the agent gets prompt-injected, blast radius is bounded.

### 4. Encrypt your `.env` at rest if backed up

Cloud-syncing `claudeclaw/.env` to Dropbox/iCloud means a compromised cloud account = compromised tokens. Either don't sync it, or pre-encrypt with `gpg -c .env`.

### 5. Audit the hooks

`.claude/hooks/*.sh` run on every tool call with full user privileges. Review them when you clone the repo, and after every `git pull`. They're under 100 lines each.

### 6. Watch for suspicious agent behavior

- Unexpected `Bash` calls in your Telegram tool-call stream.
- The agent making outbound network calls to unfamiliar hosts.
- Files appearing in your home directory you didn't ask for.

If something looks wrong: `claudeclaw stop`, inspect, and revoke tokens before resuming.

## Known security limitations

- **Channels are in research preview.** Anthropic's `--dangerously-load-development-channels` flag is required because the forked plugin isn't on the official allowlist. The TUI confirmation on every launch is a feature, not a bug — Anthropic gates it deliberately. Submission to the official allowlist is on the roadmap.
- **No automated tests for security regressions.** Bash scripts can subtly change permission semantics on edits. Manual review of every PR is the current gate.
- **`tmux` session names are predictable.** A malicious local user could `tmux kill-session -t claudeclaw` to disrupt your session. Mitigated by file permissions on `tmux` socket.

## Disclosure history

- *(none yet)*

---

claudeclaw is a side project. Security is taken seriously but response time is "when I get to it." If you find something critical, mark "URGENT" in the email subject and I'll prioritize.
