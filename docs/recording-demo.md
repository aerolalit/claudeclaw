# Recording the README demo GIF

The README references `assets/demo.gif` near the top. This is the highest-leverage piece of repo polish — without it, claudeclaw looks like a shell script. With it, the value prop is obvious in 10 seconds.

## What to capture

A single Telegram interaction that shows off the headline features in one continuous flow. The story:

1. **You send a message from Telegram on your phone.**
   Something with substance: *"check my recent commits and tell me what stands out"*, *"summarize today's daily note"*, *"what's the weather like for biking later?"*
2. **Bot reacts 👀 immediately.** This is the "I see you" beat — visible on screen.
3. **Tool-call streaming begins.** A second message appears with `🔄 Bash(...)`, `🔄 Read(...)`, etc. as the agent works.
4. **Tool calls update live** as new tools fire (`✅` replacing `🔄`).
5. **Final reply lands** with proper formatting (bold, bullets, code block).
6. **Tool-call message disappears** when the turn ends (the cleanup hook deletes it).

That sequence is genuinely the product. Showing it once is enough.

## Recommended tools

### macOS

- **CleanShot X** — best UX, $29 one-time, exports clean GIFs at any size.
- **Kap** ([free, open-source](https://getkap.co)) — captures a region, exports to GIF/MP4. Good enough.
- **QuickTime + ffmpeg** — record `.mov` with QuickTime, convert with `ffmpeg -i in.mov -vf "fps=12,scale=720:-1:flags=lanczos" -loop 0 demo.gif`. Free.

### Linux

- **peek** ([github.com/phw/peek](https://github.com/phw/peek)) — region capture, GIF export.
- **OBS Studio + ffmpeg** — for the same workflow as QuickTime.

### Phone-side

You're capturing both the terminal and the phone. Two options:

1. **Mirror your phone to the desktop** (QuickTime → "New Movie Recording" → set source to your iPhone via USB; Android: scrcpy). Then capture the desktop screen including the mirrored phone view. Best result.
2. **Side-by-side composite** — record the terminal alone, record the phone alone, splice them with iMovie / DaVinci Resolve. More work but works for any setup.

I'd start with option 1 for an iPhone or option 2 otherwise.

## Target specs

- **Format:** GIF (or animated WebP if you want better compression — GitHub renders both).
- **Dimensions:** 720px wide max. GitHub renders at 100% up to ~700px before scaling.
- **Length:** 8-15 seconds. The full Telegram-streaming flow fits in 10s easily.
- **Frame rate:** 10-12 fps. Higher rates bloat the file with no UX win.
- **File size:** Keep under 5 MB. GitHub raw images stream slowly above that.
- **Audio:** None — GIFs don't carry audio anyway.

## ffmpeg recipe (most reliable)

If you record a `.mov` or `.mp4` with anything else, this gives you a clean GIF:

```bash
ffmpeg -i input.mov \
  -vf "fps=12,scale=720:-1:flags=lanczos,split[s0][s1];[s0]palettegen[p];[s1][p]paletteuse" \
  -loop 0 \
  assets/demo.gif
```

Two-pass palette generation (the `split[s0][s1]...palettegen...paletteuse` chain) gets you a high-quality GIF in one command instead of bloated default ffmpeg output.

## Trim before exporting

Don't ship the whole "I'm setting up to record" intro. Trim the source file to start mid-action and end as soon as the final reply lands. Every second of fluff is ~50 KB.

## After you have the GIF

```bash
# from repo root
mkdir -p assets
cp /path/to/demo.gif assets/demo.gif
git add assets/demo.gif
git commit -m "Add README demo GIF"
git push
```

`assets/` is already un-ignored in `.gitignore` for tracked files (the strict-allowlist gitignore lets binary files through if they live under an explicitly un-ignored path — see the next step).

If `git add assets/demo.gif` is rejected by gitignore, add this to `.gitignore` once:

```
!assets/
!assets/**
```

## Optional: a second GIF for a specific feature

The headline GIF should show end-to-end. A second, narrower GIF can show off something specific:

- **`claudeclaw doctor`** running and showing 19/19 checks pass.
- **`/mind:standup`** typed in Telegram, reply rendering with proper markdown.
- **The `ask` tool** — agent asks "deploy main or dev?" with inline buttons, you tap, agent continues.

If you do this, embed each in its own section of the README. Don't pile them all near the top — one hero GIF, supporting GIFs scattered.

## What NOT to capture

- Pixelated phone screenshots (use real device-mirroring).
- The dev-channels confirmation prompt at startup. Boring, also visually scary for new users.
- Your real bot token or chat content. Use a test account if your real chat is sensitive.

## Why this matters

Most users decide whether to install something in under 30 seconds. A GIF lets them skip reading the README and *see* the product. claudeclaw's whole pitch ("Claude Code, but reachable from your phone, with live streaming") is **visual**. Telling people about it is third-best; showing them is first.
