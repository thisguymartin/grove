#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────────
# Grove Installer
# ─────────────────────────────────────────────

GROVE_DIR="${GROVE_DIR:-$HOME/workspace/grove}"
SHELL_RC=""

# Detect shell config file
if [[ "$SHELL" == *"zsh"* ]]; then
  SHELL_RC="$HOME/.zshrc"
elif [[ "$SHELL" == *"bash"* ]]; then
  SHELL_RC="$HOME/.bashrc"
else
  SHELL_RC="$HOME/.profile"
fi

echo "🌳 Installing Grove..."
echo "   Directory : $GROVE_DIR"
echo "   Shell RC  : $SHELL_RC"
echo ""

# ── Step 1: Clone (skip if already exists) ──
if [[ -d "$GROVE_DIR" ]]; then
  echo "✓ Grove already cloned at $GROVE_DIR — pulling latest..."
  git -C "$GROVE_DIR" pull --ff-only
else
  echo "→ Cloning grove..."
  git clone https://github.com/thisguymartin/grove.git "$GROVE_DIR"
fi

# ── Step 2: Install brew dependencies ──
if ! command -v brew &>/dev/null; then
  echo "⚠️  Homebrew not found. Install it first: https://brew.sh"
  exit 1
fi

echo "→ Installing brew dependencies..."
brew bundle --file="$GROVE_DIR/brewfile"

# ── Step 3: Source aliases (idempotent) ──
SOURCE_LINE="source $GROVE_DIR/git-worktree-aliases.sh"

if grep -qF "$SOURCE_LINE" "$SHELL_RC" 2>/dev/null; then
  echo "✓ Aliases already in $SHELL_RC"
else
  echo "" >> "$SHELL_RC"
  echo "# Grove — git worktree workspace" >> "$SHELL_RC"
  echo "$SOURCE_LINE" >> "$SHELL_RC"
  echo "✓ Added aliases to $SHELL_RC"
fi

# ── Step 4: Reload shell ──
echo ""
echo "✅ Grove installed!"
echo ""
echo "   Reload your shell:"
echo "     source $SHELL_RC"
echo ""
echo "   Then cd into any git repo and run:"
echo "     grove"
