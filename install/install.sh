#!/usr/bin/env bash
# Grove Installer/Uninstaller
#
# Usage:
#   bash install.sh               # Install to default (~/.local/share/grove)
#   bash install.sh --uninstall   # Remove Grove and shell integrations
#   GROVE_DIR=~/my/path bash install.sh
#
# Re-running install always does a clean reinstall (force-deletes existing install).

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
        fish) echo "$HOME/.config/fish/config.fish" ;;
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

cleanup_rc_file() {
    local rc_file="$1"

    [[ -f "$rc_file" ]] || return 0

    cp "$rc_file" "${rc_file}.bak"
    sed -i.tmp '/# Grove .*git worktree workspace/d' "$rc_file"
    sed -i.tmp '/git-worktree-aliases\.sh/d' "$rc_file"
    sed -i.tmp '/git-worktree-aliases\.fish/d' "$rc_file"
    sed -i.tmp '/alias gwt=.*git-worktree\.sh/d' "$rc_file"
    rm -f "${rc_file}.tmp"
}

cleanup_all_rc_files() {
    local rc_files=(
        "$HOME/.zshrc"
        "$HOME/.bashrc"
        "$HOME/.bash_profile"
        "$HOME/.profile"
        "$HOME/.config/fish/config.fish"
    )

    for candidate in "${rc_files[@]}"; do
        cleanup_rc_file "$candidate"
    done
}

cleanup_legacy_installs() {
    local legacy_dirs=(
        "$HOME/workspace/grove"
        "$HOME/.local/share/grove"
    )

    for dir in "${legacy_dirs[@]}"; do
        [[ "$dir" == "$GROVE_DIR" ]] && continue
        [[ -d "$dir" ]] || continue
        info "Removing legacy Grove installation at $dir..."
        rm -rf "$dir"
    done
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
        # Strip ANSI color codes before matching — zellij wraps session names in escape sequences
        grove_sessions=$(zellij list-sessions 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g' | grep -o 'grove-[^ ]*' || true)
        if [[ -n "$grove_sessions" ]]; then
            info "Killing existing Grove Zellij sessions..."
            while IFS= read -r session; do
                zellij kill-session "$session" 2>/dev/null || true
                zellij delete-session "$session" 2>/dev/null || true
                success "Removed session: $session"
            done <<< "$grove_sessions"
        fi
    fi

    # 2. Clean old shell integration and legacy installs
    info "Cleaning previous Grove shell integration..."
    cleanup_all_rc_files
    cleanup_legacy_installs

    # 3. Clone (force-delete existing install for a clean slate)
    if [[ -d "$GROVE_DIR" ]]; then
        info "Removing existing Grove installation at $GROVE_DIR..."
        rm -rf "$GROVE_DIR"
    fi
    info "Cloning Grove repository..."
    mkdir -p "$(dirname "$GROVE_DIR")"
    git clone "$REPO_URL" "$GROVE_DIR"

    # 4. Install Dependencies
    if command -v brew &>/dev/null; then
        info "Installing dependencies via Homebrew..."
        brew bundle --file="$GROVE_DIR/brewfile" || warn "Brew bundle failed. You may need to install dependencies manually."
    fi

    # 5. Wire up shell aliases
    local shell_name
    shell_name=$(basename "$SHELL")

    local source_line aliases_file
    if [[ "$shell_name" == "fish" ]]; then
        aliases_file="$GROVE_DIR/git-worktree-aliases.fish"
        source_line="source $aliases_file"
    else
        aliases_file="$GROVE_DIR/git-worktree-aliases.sh"
        source_line="source $aliases_file"
    fi

    if grep -qF "$source_line" "$rc_file" 2>/dev/null; then
        success "Shell integration already present in $rc_file"
    else
        info "Adding shell integration to $rc_file..."
        mkdir -p "$(dirname "$rc_file")"
        echo "" >> "$rc_file"
        echo "# Grove — git worktree workspace" >> "$rc_file"
        if [[ "$shell_name" == "fish" ]]; then
            echo "if test -f \"$aliases_file\"; $source_line; end" >> "$rc_file"
        else
            echo "[[ -f \"$aliases_file\" ]] && $source_line" >> "$rc_file"
        fi
        success "Added aliases to $rc_file"
    fi

    # 6. Optional 'gwt' alias
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
        grove_sessions=$(zellij list-sessions 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g' | grep -o 'grove-[^ ]*' || true)
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
        sed -i.tmp "/source.*grove\/git-worktree-aliases\.sh/d" "$rc_file"
        sed -i.tmp "/source.*grove\/git-worktree-aliases\.fish/d" "$rc_file"
        sed -i.tmp "/if test -f.*grove\/git-worktree-aliases\.fish/d" "$rc_file"
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

# Parse flags
ACTION="install"
for arg in "$@"; do
    case "$arg" in
        --uninstall|-u) ACTION="uninstall" ;;
        --help|-h) ACTION="help" ;;
    esac
done

if [[ "$ACTION" == "uninstall" ]]; then
    do_uninstall
elif [[ "$ACTION" == "help" ]]; then
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
    echo "  GROVE_DIR          Override the installation directory (default: ~/.local/share/grove)"
else
    do_install
fi
