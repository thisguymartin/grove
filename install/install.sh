#!/usr/bin/env bash
# Grove Installer/Uninstaller
#
# Usage:
#   bash install.sh               # Install to default (~/workspace/grove)
#   bash install.sh --uninstall   # Remove Grove and shell integrations
#   GROVE_DIR=~/my/path bash install.sh
#
# This script is idempotent and safe to run multiple times.

set -euo pipefail

# ─── Configuration ────────────────────────────────────────────────────────────

GROVE_DIR="${GROVE_DIR:-$HOME/.local/share/grove}"
REPO_URL="https://github.com/thisguymartin/grove.git"

# Colors for output
BOLD="$(tput bold 2>/dev/null || echo '')"
GREEN="$(tput setaf 2 2>/dev/null || echo '')"
YELLOW="$(tput setaf 3 2>/dev/null || echo '')"
RED="$(tput setaf 1 2>/dev/null || echo '')"
RESET="$(tput sgr0 2>/dev/null || echo '')"

info() { echo "${GREEN}→${RESET} $1"; }
warn() { echo "${YELLOW}⚠️${RESET} $1"; }
error() { echo "${RED}error:${RESET} $1" >&2; exit 1; }
success() { echo "${GREEN}✓${RESET} $1"; }

# ─── Helpers ──────────────────────────────────────────────────────────────────

detect_shell_rc() {
    local shell_name
    shell_name=$(basename "$SHELL")
    
    case "$shell_name" in
        zsh)  echo "$HOME/.zshrc" ;;
        bash) 
            if [[ "$OSTYPE" == "darwin"* ]]; then
                echo "$HOME/.bash_profile"
            else
                echo "$HOME/.bashrc"
            fi
            ;;
        *)    echo "$HOME/.profile" ;;
    esac
}

check_prereqs() {
    if ! command -v git &>/dev/null; then
        error "git is not installed. Please install git first."
    fi
    if ! command -v brew &>/dev/null; then
        warn "Homebrew not found. Some dependencies might fail to install."
        warn "Install it from https://brew.sh for the best experience."
    fi
}

# ─── Installation ─────────────────────────────────────────────────────────────

do_install() {
    local rc_file
    rc_file=$(detect_shell_rc)

    echo "${BOLD}🌳 Installing Grove...${RESET}"
    echo "   Directory : $GROVE_DIR"
    echo "   Shell RC  : $rc_file"
    echo ""

    check_prereqs

    # 1. Kill existing Grove Zellij sessions
    if command -v zellij &>/dev/null; then
        local grove_sessions
        grove_sessions=$(zellij list-sessions 2>/dev/null | grep -o 'grove-[^ ]*' || true)
        if [[ -n "$grove_sessions" ]]; then
            info "Killing existing Grove Zellij sessions..."
            while IFS= read -r session; do
                zellij kill-session "$session" 2>/dev/null || true
                zellij delete-session "$session" 2>/dev/null || true
                success "Removed session: $session"
            done <<< "$grove_sessions"
        fi
    fi

    # 2. Clone or Update
    if [[ -d "$GROVE_DIR" ]]; then
        info "Grove already exists at $GROVE_DIR. Updating..."
        git -C "$GROVE_DIR" pull --ff-only || warn "Failed to pull latest changes."
    else
        info "Cloning Grove repository..."
        mkdir -p "$(dirname "$GROVE_DIR")"
        git clone "$REPO_URL" "$GROVE_DIR"
    fi

    # 3. Install Dependencies
    if command -v brew &>/dev/null; then
        info "Installing dependencies via Homebrew..."
        brew bundle --file="$GROVE_DIR/brewfile" || warn "Brew bundle failed. You may need to install dependencies manually."
    fi

    # 4. Wire up shell aliases
    local source_line="source $GROVE_DIR/git-worktree-aliases.sh"
    if grep -qF "$source_line" "$rc_file" 2>/dev/null; then
        success "Shell integration already present in $rc_file"
    else
        info "Adding shell integration to $rc_file..."
        echo "" >> "$rc_file"
        echo "# Grove — git worktree workspace" >> "$rc_file"
        echo "[[ -f \"$GROVE_DIR/git-worktree-aliases.sh\" ]] && $source_line" >> "$rc_file"
        success "Added aliases to $rc_file"
    fi

    # 5. Optional 'gwt' alias
    local gwt_alias="alias gwt='$GROVE_DIR/git-worktree.sh'"
    if ! grep -qF "$gwt_alias" "$rc_file" 2>/dev/null; then
        echo ""
        read -p "   Do you want to add the 'gwt' alias for the worktree toolkit? [y/N] " -n 1 -r
        echo ""
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            echo "$gwt_alias" >> "$rc_file"
            success "Added 'gwt' alias to $rc_file"
        fi
    fi

    echo ""
    echo "${BOLD}${GREEN}✅ Grove installation complete!${RESET}"
    echo ""
    echo "   To start using Grove, reload your shell:"
    echo "     ${BOLD}source $rc_file${RESET}"
    echo ""
    echo "   Then navigate to any git repository and run:"
    echo "     ${BOLD}grove${RESET}"
    echo ""
}

# ─── Uninstallation ───────────────────────────────────────────────────────────

do_uninstall() {
    local rc_file
    rc_file=$(detect_shell_rc)

    echo "${BOLD}${YELLOW}🗑  Uninstalling Grove...${RESET}"
    
    # 1. Kill all Grove Zellij sessions
    if command -v zellij &>/dev/null; then
        local grove_sessions
        grove_sessions=$(zellij list-sessions 2>/dev/null | grep -o 'grove-[^ ]*' || true)
        if [[ -n "$grove_sessions" ]]; then
            info "Killing Grove Zellij sessions..."
            while IFS= read -r session; do
                zellij kill-session "$session" 2>/dev/null || true
                zellij delete-session "$session" 2>/dev/null || true
                success "Removed session: $session"
            done <<< "$grove_sessions"
        fi
    fi

    # 2. Remove from shell RC
    if [[ -f "$rc_file" ]]; then
        info "Removing Grove integration from $rc_file..."
        # Create a backup
        cp "$rc_file" "${rc_file}.bak"
        
        # Use a temporary file to filter out Grove lines
        # We look for the comment, the source line, or the gwt alias
        sed -i.tmp '/# Grove — git worktree workspace/d' "$rc_file"
        sed -i.tmp "/source.*grove\/git-worktree-aliases.sh/d" "$rc_file"
        sed -i.tmp "/alias gwt=.*grove\/git-worktree.sh/d" "$rc_file"
        rm -f "${rc_file}.tmp"
        
        success "Removed Grove lines from $rc_file (backup saved to ${rc_file}.bak)"
    fi

    # 3. Remove directory
    if [[ -d "$GROVE_DIR" ]]; then
        read -p "   Do you want to delete the Grove directory at $GROVE_DIR? [y/N] " -n 1 -r
        echo ""
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            info "Removing $GROVE_DIR..."
            rm -rf "$GROVE_DIR"
            success "Directory deleted."
        else
            info "Skipping directory removal."
        fi
    fi

    echo ""
    echo "${BOLD}${GREEN}✨ Grove has been uninstalled.${RESET}"
    echo "   Please restart your terminal or source $rc_file to clear aliases."
    echo ""
}

# ─── Main ─────────────────────────────────────────────────────────────────────

# Handle --uninstall or -u
if [[ "${1:-}" == "--uninstall" ]] || [[ "${1:-}" == "-u" ]]; then
    do_uninstall
elif [[ "${1:-}" == "--help" ]] || [[ "${1:-}" == "-h" ]]; then
    echo "Grove Installer"
    echo ""
    echo "Usage:"
    echo "  install.sh [options]"
    echo ""
    echo "Options:"
    echo "  -u, --uninstall    Remove Grove and its shell integrations"
    echo "  -h, --help         Show this help message"
    echo ""
    echo "Environment Variables:"
    echo "  GROVE_DIR          Override the installation directory (default: ~/workspace/grove)"
else
    do_install
fi
