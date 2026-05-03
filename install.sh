#!/usr/bin/env bash
# install.sh — one-line installer for claudeclaw.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/aerolalit/claudeclaw/main/install.sh | bash
#
# Optional install location override:
#   CLAUDECLAW_DIR=/custom/path curl -fsSL ... | bash
#
# What it does:
#   1. Auto-installs prereqs (git, curl, node/npm) if missing — apt/brew/dnf/pacman.
#   2. Clones the repo to ~/claudeclaw (or $CLAUDECLAW_DIR).
#      If the dir already exists, runs `git pull` instead of refusing.
#   3. Hands off to start.sh, which walks you through the rest interactively.

set -euo pipefail

REPO_URL="https://github.com/aerolalit/claudeclaw.git"
INSTALL_DIR="${CLAUDECLAW_DIR:-$HOME/claudeclaw}"

# --- Detect package manager once ---
PKG=""
if   command -v apt-get  >/dev/null 2>&1; then PKG="apt"
elif command -v brew     >/dev/null 2>&1; then PKG="brew"
elif command -v dnf      >/dev/null 2>&1; then PKG="dnf"
elif command -v pacman   >/dev/null 2>&1; then PKG="pacman"
elif command -v apk      >/dev/null 2>&1; then PKG="apk"
fi

apt_pkg() { sudo apt-get update -qq && sudo apt-get install -y "$@"; }
brew_pkg() { brew install "$@"; }
dnf_pkg() { sudo dnf install -y "$@"; }
pacman_pkg() { sudo pacman -S --noconfirm "$@"; }
apk_pkg() { sudo apk add "$@"; }

install_pkg() {
  case "$PKG" in
    apt)    apt_pkg "$@" ;;
    brew)   brew_pkg "$@" ;;
    dnf)    dnf_pkg "$@" ;;
    pacman) pacman_pkg "$@" ;;
    apk)    apk_pkg "$@" ;;
    *)
      echo "ERROR: no known package manager (apt/brew/dnf/pacman/apk)." >&2
      echo "  Install manually: $*" >&2
      exit 1
      ;;
  esac
}

ensure() {
  local cmd="$1"; shift
  local pkg_name="${1:-$cmd}"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "→ $cmd not found, installing..."
    install_pkg "$pkg_name"
  fi
}

echo "=== claudeclaw installer ==="
echo "  install dir:    $INSTALL_DIR"
echo "  package manager: ${PKG:-none}"
echo

# --- Prereqs ---
ensure git
ensure curl

# Node 18+ — package name varies by distro.
if ! command -v node >/dev/null 2>&1; then
  echo "→ node not found, installing..."
  # Prefer just `nodejs` on apt/dnf — npm ships bundled with both Debian's
  # and NodeSource's nodejs packages, and asking for both can hit a
  # conflict on systems where NodeSource's repo is configured.
  case "$PKG" in
    apt)    apt_pkg nodejs ;;
    brew)   brew_pkg node ;;
    dnf)    dnf_pkg nodejs ;;
    pacman) pacman_pkg nodejs npm ;;
    apk)    apk_pkg nodejs npm ;;
    *)
      echo "ERROR: install Node.js 18+ manually: https://nodejs.org" >&2
      exit 1
      ;;
  esac
fi
# Some distros split npm into a separate package — re-check and install if missing.
if ! command -v npm >/dev/null 2>&1; then
  echo "→ npm not bundled with nodejs, installing separately..."
  case "$PKG" in
    apt)    apt_pkg npm ;;
    brew)   : ;;  # npm bundled with brew node
    dnf)    dnf_pkg npm ;;
    pacman) : ;;  # already requested
    apk)    : ;;  # already requested
    *)
      echo "ERROR: install npm manually." >&2
      exit 1
      ;;
  esac
fi

# --- Clone or update ---
if [ -d "$INSTALL_DIR/.git" ]; then
  echo "→ existing claudeclaw at $INSTALL_DIR, pulling latest..."
  git -C "$INSTALL_DIR" pull --ff-only
elif [ -e "$INSTALL_DIR" ]; then
  echo "ERROR: $INSTALL_DIR exists but is not a git checkout." >&2
  echo "  Move or remove it, or set CLAUDECLAW_DIR to a different path." >&2
  exit 1
else
  echo "→ cloning claudeclaw to $INSTALL_DIR..."
  git clone --depth=1 "$REPO_URL" "$INSTALL_DIR"
fi

echo
echo "✔ claudeclaw installed at $INSTALL_DIR"

# --- Install the `claudeclaw` shim into ~/.local/bin ---
BIN_DIR="$HOME/.local/bin"
SHIM="$BIN_DIR/claudeclaw"
mkdir -p "$BIN_DIR"
ln -sf "$INSTALL_DIR/start.sh" "$SHIM"
echo "✔ installed 'claudeclaw' command at $SHIM"

# --- Help users whose shell doesn't have ~/.local/bin on PATH ---
PATH_HINT=""
case ":$PATH:" in
  *":$BIN_DIR:"*)
    : # already on PATH
    ;;
  *)
    # Pick the right rc file based on shell.
    rc_file="$HOME/.bashrc"
    case "${SHELL:-}" in
      */zsh) rc_file="$HOME/.zshrc" ;;
      */fish) rc_file="$HOME/.config/fish/config.fish" ;;
    esac
    PATH_HINT="$rc_file"
    ;;
esac

cd "$INSTALL_DIR"

# Tell the user the next step. When piped from curl, stdin is closed,
# so we can't run start.sh interactively here — they kick it off
# themselves. Either way they end up with a working `claudeclaw` command.
echo
echo "─────────────────────────────────────────────────────────────────"
echo " Next: start a session"
echo "─────────────────────────────────────────────────────────────────"
if [ -n "$PATH_HINT" ]; then
  echo
  echo " First add ~/.local/bin to PATH (one-time):"
  echo "   echo 'export PATH=\"\$HOME/.local/bin:\$PATH\"' >> $PATH_HINT"
  echo "   source $PATH_HINT"
  echo
fi
echo " Then run:"
echo
echo "   claudeclaw"
echo
echo " (Or once: cd $INSTALL_DIR && ./start.sh)"
echo
echo " It walks you through Claude Code auth, plugin install,"
echo " bot token, and Telegram pairing — then keeps the session"
echo " running in tmux so it survives terminal close."
echo "─────────────────────────────────────────────────────────────────"

# If this is an interactive shell (not curl-piped), launch immediately.
if [ -t 0 ]; then
  echo
  exec ./start.sh
fi
