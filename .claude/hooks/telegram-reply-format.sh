#!/usr/bin/env bash
# telegram-reply-format.sh — PreToolUse hook scoped to the Telegram reply tool.
# Transforms standard markdown in the `text` field into Telegram MarkdownV2
# (escaping all literal special chars) and forces format="markdownv2", so the
# agent can write normal markdown and have it render correctly in Telegram
# without wasting tokens on manual escaping.
#
# Markdown conversions handled:
#   **bold**       → *bold*           (MarkdownV2 uses single-asterisk for bold)
#   *italic*       → _italic_         (MarkdownV2 uses underscores for italic)
#   `code`         → `code`           (no conversion; contents not escaped)
#   ```fenced```   → ```fenced```     (no conversion; contents not escaped)
#   [text](url)    → [text](url)      (escapes text and url separately)
#
# All other instances of MarkdownV2 specials (_ * [ ] ( ) ~ > # + - = | { } . ! \)
# in literal text get backslash-escaped.
#
# Bails (no output, exit 0) for any tool other than the reply tool, leaving
# the call unchanged. Bails on parse failure too — never blocks the agent.

set -u
TG_STATE_DIR="${TELEGRAM_STATE_DIR:-$HOME/.claude/channels/telegram}"
mkdir -p "$TG_STATE_DIR" 2>/dev/null || true
exec 2>>"$TG_STATE_DIR/stream.log"

INPUT=$(cat)
[ -z "$INPUT" ] && exit 0

TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
[ "$TOOL" != "mcp__plugin_telegram_telegram__reply" ] && exit 0

TOOL_INPUT=$(echo "$INPUT" | jq -c '.tool_input // {}' 2>/dev/null)
[ -z "$TOOL_INPUT" ] || [ "$TOOL_INPUT" = "{}" ] && exit 0

TEXT=$(echo "$TOOL_INPUT" | jq -r '.text // empty' 2>/dev/null)
[ -z "$TEXT" ] && exit 0

# --- Markdown → MarkdownV2 transform via awk -------------------------------
# Strategy: protect markdown-intent patterns by swapping them for unique
# sentinels, escape every literal special char in what remains, then restore
# the sentinels with proper MarkdownV2 syntax. Sentinels use control bytes
# (\x01..\x05) that won't appear in normal text.
NEW_TEXT=$(printf '%s' "$TEXT" | awk '
  BEGIN {
    SOH = sprintf("%c", 1)   # fenced code block sentinel prefix
    STX = sprintf("%c", 2)   # inline code sentinel prefix
    ETX = sprintf("%c", 3)   # link sentinel prefix
    EOT = sprintf("%c", 4)   # bold sentinel prefix
    ENQ = sprintf("%c", 5)   # italic sentinel prefix
    SEP = sprintf("%c", 6)   # field separator within sentinel payloads
    fenced_n = 0; inline_n = 0; link_n = 0; bold_n = 0; italic_n = 0
    text = ""
  }
  { text = (NR == 1 ? $0 : text "\n" $0) }
  END {
    # 0. Line-level pre-pass: convert markdown headers and bullets into shapes
    #    that MarkdownV2 can actually render.
    #    - Headers (# / ## / ###) -> wrap in **bold** (no header support in MD2).
    #    - Bullets (-, *) -> replace with "•" (no bullet syntax in MD2; the
    #      glyph just renders as text but reads correctly to humans).
    out = ""
    n = split(text, lines, "\n")
    for (i = 1; i <= n; i++) {
      ln = lines[i]
      # Strip leading whitespace count for indentation preservation.
      lead = ""
      while (length(ln) > 0 && (substr(ln, 1, 1) == " " || substr(ln, 1, 1) == "\t")) {
        lead = lead substr(ln, 1, 1)
        ln = substr(ln, 2)
      }
      # Header: starts with 1-6 # followed by space.
      if (match(ln, /^#{1,6}[ \t]+/)) {
        content = substr(ln, RLENGTH + 1)
        ln = "**" content "**"
      }
      # Bullet: starts with "- " or "* " (after the leading whitespace).
      else if (match(ln, /^[-*][ \t]+/)) {
        ln = "• " substr(ln, RLENGTH + 1)
      }
      out = (i == 1 ? "" : out "\n") lead ln
    }
    text = out

    # 1. Extract fenced code blocks ``` ... ``` (greedy, multiline)
    out = ""
    while (match(text, /```[^`]*```/)) {
      out = out substr(text, 1, RSTART - 1)
      block = substr(text, RSTART + 3, RLENGTH - 6)
      fenced_arr[fenced_n] = block
      out = out SOH fenced_n SOH
      fenced_n++
      text = substr(text, RSTART + RLENGTH)
    }
    text = out text

    # 2. Extract inline code `...`
    out = ""
    while (match(text, /`[^`]+`/)) {
      out = out substr(text, 1, RSTART - 1)
      code = substr(text, RSTART + 1, RLENGTH - 2)
      inline_arr[inline_n] = code
      out = out STX inline_n STX
      inline_n++
      text = substr(text, RSTART + RLENGTH)
    }
    text = out text

    # 3. Extract links [text](url)
    out = ""
    while (match(text, /\[[^\]]+\]\([^\)]+\)/)) {
      out = out substr(text, 1, RSTART - 1)
      m = substr(text, RSTART, RLENGTH)
      # Split on "](" — robust because m matches the strict pattern above
      bp = index(m, "](")
      ltext = substr(m, 2, bp - 2)
      lurl = substr(m, bp + 2, length(m) - bp - 2)
      link_arr[link_n] = ltext SEP lurl
      out = out ETX link_n ETX
      link_n++
      text = substr(text, RSTART + RLENGTH)
    }
    text = out text

    # 4. Extract **bold** (do before *italic* to avoid */ greedy collision)
    out = ""
    while (match(text, /\*\*[^*]+\*\*/)) {
      out = out substr(text, 1, RSTART - 1)
      b = substr(text, RSTART + 2, RLENGTH - 4)
      bold_arr[bold_n] = b
      out = out EOT bold_n EOT
      bold_n++
      text = substr(text, RSTART + RLENGTH)
    }
    text = out text

    # 5. Extract *italic*
    out = ""
    while (match(text, /\*[^*]+\*/)) {
      out = out substr(text, 1, RSTART - 1)
      it = substr(text, RSTART + 1, RLENGTH - 2)
      italic_arr[italic_n] = it
      out = out ENQ italic_n ENQ
      italic_n++
      text = substr(text, RSTART + RLENGTH)
    }
    text = out text

    # 6. Escape MarkdownV2 specials in remaining literal text.
    # Specials: _ * [ ] ( ) ~ ` > # + - = | { } . ! \
    # Backslash must come first so we do not double-escape.
    # awk gsub replacement: "\\X" in source produces "\X" in output.
    gsub(/\\/, "\\\\", text)
    gsub(/_/,  "\\_", text)
    gsub(/\*/, "\\*", text)
    gsub(/\[/, "\\[", text)
    gsub(/\]/, "\\]", text)
    gsub(/\(/, "\\(", text)
    gsub(/\)/, "\\)", text)
    gsub(/~/,  "\\~", text)
    gsub(/`/,  "\\`", text)
    gsub(/>/,  "\\>", text)
    gsub(/#/,  "\\#", text)
    gsub(/\+/, "\\+", text)
    gsub(/-/,  "\\-", text)
    gsub(/=/,  "\\=", text)
    gsub(/\|/, "\\|", text)
    gsub(/\{/, "\\{", text)
    gsub(/\}/, "\\}", text)
    gsub(/\./, "\\.", text)
    gsub(/!/,  "\\!", text)

    # 7. Restore sentinels with MarkdownV2 syntax.
    # Italic — wrap stored content in underscores. Content is plain text with
    # no formatting allowed inside (we already extracted nested patterns above,
    # so this is safe), but specials inside still need escaping.
    for (i = 0; i < italic_n; i++) {
      content = italic_arr[i]
      content = escape_specials(content)
      gsub(ENQ i ENQ, "_" content "_", text)
    }
    # Bold — single asterisks in MarkdownV2.
    for (i = 0; i < bold_n; i++) {
      content = bold_arr[i]
      content = escape_specials(content)
      gsub(EOT i EOT, "*" content "*", text)
    }
    # Links — [text](url) with text and url both escaped per MarkdownV2 rules
    # (text: backslash-escape "[" "]" "\\"; url: backslash-escape ")" "\\").
    for (i = 0; i < link_n; i++) {
      pair = link_arr[i]
      sp = index(pair, SEP)
      ltext = substr(pair, 1, sp - 1)
      lurl = substr(pair, sp + 1)
      ltext = escape_link_text(ltext)
      lurl = escape_link_url(lurl)
      gsub(ETX i ETX, "[" ltext "](" lurl ")", text)
    }
    # Inline code — contents kept verbatim except `\` and `` ` `` need escaping
    # per MarkdownV2 rules.
    for (i = 0; i < inline_n; i++) {
      content = inline_arr[i]
      content = escape_code(content)
      gsub(STX i STX, "`" content "`", text)
    }
    # Fenced code blocks — same escape rules as inline code, wrapped in ```.
    for (i = 0; i < fenced_n; i++) {
      content = fenced_arr[i]
      content = escape_code(content)
      gsub(SOH i SOH, "```" content "```", text)
    }

    print text
  }

  function escape_specials(s,    out) {
    out = s
    gsub(/\\/, "\\\\", out); gsub(/_/, "\\_", out); gsub(/\*/, "\\*", out)
    gsub(/\[/, "\\[", out); gsub(/\]/, "\\]", out); gsub(/\(/, "\\(", out)
    gsub(/\)/, "\\)", out); gsub(/~/, "\\~", out); gsub(/`/, "\\`", out)
    gsub(/>/, "\\>", out); gsub(/#/, "\\#", out); gsub(/\+/, "\\+", out)
    gsub(/-/, "\\-", out); gsub(/=/, "\\=", out); gsub(/\|/, "\\|", out)
    gsub(/\{/, "\\{", out); gsub(/\}/, "\\}", out); gsub(/\./, "\\.", out)
    gsub(/!/, "\\!", out)
    return out
  }
  function escape_link_text(s,    out) {
    out = s
    gsub(/\\/, "\\\\", out); gsub(/\[/, "\\[", out); gsub(/\]/, "\\]", out)
    return out
  }
  function escape_link_url(s,    out) {
    out = s
    gsub(/\\/, "\\\\", out); gsub(/\)/, "\\)", out)
    return out
  }
  function escape_code(s,    out) {
    out = s
    gsub(/\\/, "\\\\", out); gsub(/`/, "\\`", out)
    return out
  }
')

# Build modified tool_input: rewrite text + force format="markdownv2".
NEW_INPUT=$(echo "$TOOL_INPUT" | jq --arg t "$NEW_TEXT" '.text = $t | .format = "markdownv2"')

# Emit hook decision: allow with modified input.
jq -n --argjson ui "$NEW_INPUT" '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    permissionDecision: "allow",
    updatedInput: $ui
  }
}'

exit 0
