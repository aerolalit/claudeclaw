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
  case "$PKG" in
    apt)    apt_pkg nodejs npm ;;
    brew)   brew_pkg node ;;
    dnf)    dnf_pkg nodejs npm ;;
    pacman) pacman_pkg nodejs npm ;;
    apk)    apk_pkg nodejs npm ;;
    *)
      echo "ERROR: install Node.js 18+ manually: https://nodejs.org" >&2
      exit 1
      ;;
  esac
fi
ensure npm

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
echo "→ launching ./start.sh..."
echo

# Hand off. exec replaces this shell so start.sh owns the terminal.
# When this script is run via `curl ... | bash`, stdin is the curl pipe (now
# closed). Re-attach stdin to the controlling TTY so start.sh's interactive
# prompts work. /dev/tty is the standard POSIX way to address the user's
# real terminal, regardless of how stdin was redirected.
cd "$INSTALL_DIR"
if [ -e /dev/tty ]; then
  exec </dev/tty
else
  echo "ERROR: no controlling TTY available — can't run interactive setup." >&2
  echo "  Try: cd $INSTALL_DIR && ./start.sh" >&2
  exit 1
fi
exec ./start.sh
