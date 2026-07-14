#!/usr/bin/env bash
# Grove Installer/Uninstaller
#
# Usage:
#   bash install.sh               # Install to default (~/.local/share/grove)
#   bash install.sh --agent codex # Install with Codex as the default agent
#   bash install.sh --local       # Symlink local checkout (for development)
#   bash install.sh --uninstall   # Remove Grove and shell integrations
#   GROVE_DIR=~/my/path bash install.sh
#
# Re-running install always does a clean reinstall (force-deletes existing install).

set -euo pipefail

# ─── Configuration ────────────────────────────────────────────────────────────

GROVE_DIR="${GROVE_DIR:-$HOME/.local/share/grove}"
REPO_URL="https://github.com/thisguymartin/grove.git"
GROVE_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/grove"
GROVE_CONFIG_FILE="$GROVE_CONFIG_DIR/config"

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

is_supported_agent() {
    case "${1:-}" in
        codex|opencode|claude|gemini|none) return 0 ;;
        *) return 1 ;;
    esac
}

select_agent_interactively() {
    local choice

    echo "${BOLD}Choose the AI agent Grove should use by default:${RESET}" >&2
    echo "  1) Codex (OpenAI)" >&2
    echo "  2) OpenCode" >&2
    echo "  3) Claude Code" >&2
    echo "  4) Gemini CLI" >&2
    echo "  5) None (worktree tools only)" >&2

    while true; do
        read -r -p "Selection [1-5]: " choice
        case "$choice" in
            1|codex) printf 'codex\n'; return 0 ;;
            2|opencode) printf 'opencode\n'; return 0 ;;
            3|claude) printf 'claude\n'; return 0 ;;
            4|gemini) printf 'gemini\n'; return 0 ;;
            5|none) printf 'none\n'; return 0 ;;
            *) warn "Choose 1, 2, 3, 4, or 5." >&2 ;;
        esac
    done
}

resolve_install_agent() {
    if [[ -n "$SELECTED_AGENT" ]]; then
        if ! is_supported_agent "$SELECTED_AGENT"; then
            error "Unsupported agent '$SELECTED_AGENT'. Use codex, opencode, claude, gemini, or none."
        fi
        return 0
    fi

    if [[ -t 0 ]]; then
        SELECTED_AGENT="$(select_agent_interactively)"
        return 0
    fi

    error "Non-interactive installation requires --agent <codex|opencode|claude|gemini|none>."
}

install_selected_agent() {
    [[ "$SELECTED_AGENT" != "none" ]] || {
        info "Skipping AI agent installation."
        return 0
    }

    if command -v "$SELECTED_AGENT" >/dev/null 2>&1; then
        success "$(agent_display_name "$SELECTED_AGENT") is already installed."
        return 0
    fi

    info "Installing $(agent_display_name "$SELECTED_AGENT")..."
    case "$SELECTED_AGENT" in
        codex)
            command -v brew >/dev/null 2>&1 || error "Homebrew is required to install Codex."
            brew install --cask codex
            ;;
        opencode)
            command -v brew >/dev/null 2>&1 || error "Homebrew is required to install OpenCode."
            brew install anomalyco/tap/opencode
            ;;
        claude)
            command -v brew >/dev/null 2>&1 || error "Homebrew is required to install Claude Code."
            brew install --cask claude-code
            ;;
        gemini)
            if ! command -v npm >/dev/null 2>&1; then
                command -v brew >/dev/null 2>&1 || error "Homebrew is required to install Node.js for Gemini CLI."
                brew install node
                hash -r
            fi
            command -v npm >/dev/null 2>&1 || error "npm is required to install Gemini CLI."
            npm install -g @google/gemini-cli
            ;;
    esac
}

agent_display_name() {
    case "$1" in
        codex) echo "Codex" ;;
        opencode) echo "OpenCode" ;;
        claude) echo "Claude Code" ;;
        gemini) echo "Gemini CLI" ;;
        none) echo "none" ;;
    esac
}

write_agent_config() {
    mkdir -p "$GROVE_CONFIG_DIR"
    printf 'default_ai=%s\n' "$SELECTED_AGENT" > "$GROVE_CONFIG_FILE"
    success "Set Grove's default AI agent to $(agent_display_name "$SELECTED_AGENT")."
}

remove_agent_config() {
    rm -f "$GROVE_CONFIG_FILE"
    rmdir "$GROVE_CONFIG_DIR" 2>/dev/null || true
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

    # 3. Install grove files
    if [[ -d "$GROVE_DIR" ]] || [[ -L "$GROVE_DIR" ]]; then
        info "Removing existing Grove installation at $GROVE_DIR..."
        rm -rf "$GROVE_DIR"
    fi
    mkdir -p "$(dirname "$GROVE_DIR")"

    if $LOCAL_INSTALL; then
        # Resolve the repo root from wherever install.sh lives
        local repo_root
        repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
        info "Symlinking local checkout: $repo_root -> $GROVE_DIR"
        ln -s "$repo_root" "$GROVE_DIR"
    else
        info "Cloning Grove repository..."
        git clone "$REPO_URL" "$GROVE_DIR"
    fi

    # 4. Install Dependencies
    if command -v brew &>/dev/null; then
        info "Installing dependencies via Homebrew..."
        brew bundle --file="$GROVE_DIR/brewfile" || warn "Brew bundle failed. You may need to install dependencies manually."
    fi

    # 5. Install only the selected AI agent and save it as Grove's default
    install_selected_agent
    write_agent_config

    # 6. Wire up shell aliases
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

    echo ""
    echo "${BOLD}${GREEN}✅ Grove installation complete!${RESET}"
    echo ""
    echo "   To start using Grove, reload your shell:"
    echo "     ${BOLD}source $rc_file${RESET}"
    echo ""
    echo "   Then navigate to any git repository and run:"
    echo "     ${BOLD}grove${RESET}"
    if [[ "$SELECTED_AGENT" == "none" ]]; then
        echo ""
        echo "   Install an AI CLI later and launch it explicitly, for example:"
        echo "     ${BOLD}grove codex .${RESET}"
    fi
    echo ""
}

# ─── Uninstallation ───────────────────────────────────────────────────────────

do_uninstall() {
    local rc_file
    rc_file=$(detect_shell_rc)

    echo "${BOLD}${YELLOW}🗑  Uninstalling Grove...${RESET}"

    remove_agent_config
    
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
        # Remove the managed source line and any legacy gwt alias.
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
LOCAL_INSTALL=false
SELECTED_AGENT=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --uninstall|-u) ACTION="uninstall" ;;
        --local|-l) LOCAL_INSTALL=true ;;
        --help|-h) ACTION="help" ;;
        --agent)
            [[ $# -ge 2 ]] || error "--agent requires codex, opencode, claude, gemini, or none."
            SELECTED_AGENT="$2"
            shift
            ;;
        --agent=*) SELECTED_AGENT="${1#--agent=}" ;;
        *) error "Unknown option '$1'. Run install.sh --help for usage." ;;
    esac
    shift
done

if [[ "$ACTION" == "install" ]]; then
    resolve_install_agent
fi

if [[ "$ACTION" == "uninstall" ]]; then
    do_uninstall
elif [[ "$ACTION" == "help" ]]; then
    echo "Grove Installer"
    echo ""
    echo "Usage:"
    echo "  install.sh [options]"
    echo ""
    echo "Options:"
    echo "      --agent AGENT  Set up codex, opencode, claude, gemini, or none"
    echo "  -l, --local        Symlink local checkout instead of cloning (for development)"
    echo "  -u, --uninstall    Remove Grove and its shell integrations"
    echo "  -h, --help         Show this help message"
    echo ""
    echo "Environment Variables:"
    echo "  GROVE_DIR          Override the installation directory (default: ~/.local/share/grove)"
    echo "  XDG_CONFIG_HOME    Override the config root (default: ~/.config)"
else
    do_install
fi
