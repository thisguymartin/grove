#!/usr/bin/env bash
# Launch a Zellij workspace with one tab per git worktree.
#
# Usage:
#   ./launch-worktrees.sh                  # Use current repo
#   ./launch-worktrees.sh /path/to/repo    # Explicit repo path
#   ./launch-worktrees.sh --layout-only    # Print KDL to stdout (no launch)
#
# Each worktree gets its own Zellij tab containing:
#   Left:  lazygit focused on that worktree
#   Right: AI Agent (Claude Code / OpenCode)
#   Bottom: Workbench shell
#
# A top tab-bar shows all worktree tabs for easy navigation.
# A final "Overview" tab shows live git status across all worktrees.
#
# Options:
#   --ai <editor>    AI editor command (default: claude, or set AI_EDITOR)
#
# Tab names come from the branch name (strips "refs/heads/").
# Detached HEADs use the short commit SHA as the tab name.
#
# Requirements: git, zellij
# Optional:     lazygit (falls back to a plain shell if not installed)
#
# Attach to an existing session later with:
#   zellij attach git-worktrees

set -euo pipefail

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
REPO_PATH=""
LAYOUT_ONLY=false
SESSION_NAME="git-worktrees"
AI_EDITOR="${AI_EDITOR:-claude}"

# Tab color palette — cycles through these for each worktree tab
TAB_COLORS=("green" "blue" "yellow" "magenta" "cyan" "orange" "red")

while [[ $# -gt 0 ]]; do
    case "$1" in
        --layout-only) LAYOUT_ONLY=true; shift ;;
        --kill-all)
            echo "Killing all Zellij sessions..."
            zellij kill-all-sessions 2>/dev/null || echo "No active sessions."
            shift
            ;;
        --ai)
            AI_EDITOR="${2:?--ai requires an editor name (e.g. claude, opencode)}"
            shift 2
            ;;
        --help|-h)
            grep '^#' "$0" | head -20 | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *) REPO_PATH="$1"; shift ;;
    esac
done

REPO_PATH="${REPO_PATH:-$(pwd)}"

# ---------------------------------------------------------------------------
# Sanity checks
# ---------------------------------------------------------------------------
if ! git -C "$REPO_PATH" rev-parse --show-toplevel &>/dev/null; then
    echo "Error: '$REPO_PATH' is not inside a git repository"
    exit 1
fi

# Resolve to the actual top-level so relative paths work
REPO_PATH=$(git -C "$REPO_PATH" rev-parse --show-toplevel)

if ! command -v zellij &>/dev/null && ! $LAYOUT_ONLY; then
    echo "Error: zellij is required. Install from https://zellij.dev"
    exit 1
fi

HAS_LAZYGIT=false
command -v lazygit &>/dev/null && HAS_LAZYGIT=true

# ---------------------------------------------------------------------------
# Parse git worktrees into parallel arrays
# WT_PATHS[]   — absolute path to each worktree
# WT_BRANCHES[] — full ref (refs/heads/foo) or empty string for detached
# WT_HEADS[]   — commit SHA
# ---------------------------------------------------------------------------
WT_PATHS=()
WT_BRANCHES=()
WT_HEADS=()

# git worktree list --porcelain outputs blocks like:
#   worktree /path
#   HEAD <sha>
#   branch refs/heads/main   (or "detached")
#   (blank line)
parse_worktrees() {
    local wt="" br="" hd=""
    while IFS= read -r line; do
        case "$line" in
            worktree\ *)  wt="${line#worktree }" ;;
            branch\ *)    br="${line#branch }" ;;
            HEAD\ *)      hd="${line#HEAD }" ;;
            detached)     br="" ;;
            "")
                if [[ -n "$wt" ]]; then
                    WT_PATHS+=("$wt")
                    WT_BRANCHES+=("$br")
                    WT_HEADS+=("$hd")
                    wt=""; br=""; hd=""
                fi
                ;;
        esac
    done < <(git -C "$REPO_PATH" worktree list --porcelain)

    # Handle last block if no trailing blank line
    if [[ -n "$wt" ]]; then
        WT_PATHS+=("$wt")
        WT_BRANCHES+=("$br")
        WT_HEADS+=("$hd")
    fi
}

parse_worktrees

if [[ ${#WT_PATHS[@]} -eq 0 ]]; then
    echo "Error: no worktrees found in $REPO_PATH"
    exit 1
fi

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# Returns a human-friendly tab name for a worktree
tab_name() {
    local branch="$1" head="$2"
    if [[ -n "$branch" ]]; then
        echo "${branch#refs/heads/}"
    else
        echo "${head:0:7}"
    fi
}

# Escape a string for embedding inside a KDL double-quoted string
kdl_escape() {
    # Replace backslash first, then double-quote
    printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

# ---------------------------------------------------------------------------
# KDL layout generation
# ---------------------------------------------------------------------------
generate_layout() {
    cat <<'HEADER'
layout {
    default_tab_template {
        pane size=1 borderless=true {
            plugin location="zellij:tab-bar"
        }
        children
        pane size=1 borderless=true {
            plugin location="zellij:status-bar"
        }
    }

HEADER

    for i in "${!WT_PATHS[@]}"; do
        local path="${WT_PATHS[$i]}"
        local branch="${WT_BRANCHES[$i]}"
        local head="${WT_HEADS[$i]}"
        local name
        name=$(tab_name "$branch" "$head")
        local esc_path esc_name
        esc_path=$(kdl_escape "$path")
        esc_name=$(kdl_escape "$name")

        local esc_ai
        esc_ai=$(kdl_escape "$AI_EDITOR")

        local color_index=$((i % ${#TAB_COLORS[@]}))
        local tab_color="${TAB_COLORS[$color_index]}"

        echo "    tab name=\"$esc_name\" color=\"$tab_color\" {"

        # TOP (70%): LazyGit + AI Agent side by side
        echo "        pane split_direction=\"vertical\" size=\"70%\" {"

        # Left: lazygit (or plain shell if lazygit not installed)
        if $HAS_LAZYGIT; then
            echo "            pane command=\"lazygit\" name=\"LazyGit\" {"
            echo "                cwd \"$esc_path\""
            echo "            }"
        else
            echo "            pane name=\"git: $esc_name\" {"
            echo "                cwd \"$esc_path\""
            echo "            }"
        fi

        # Right: AI Agent
        echo "            pane command=\"$esc_ai\" name=\"AI Agent\" {"
        echo "                cwd \"$esc_path\""
        if [[ "$i" -eq 0 ]]; then
            echo "                focus true"
        fi
        echo "            }"

        echo "        }"

        # BOTTOM (30%): Workbench shell
        echo "        pane name=\"Workbench\" {"
        echo "            cwd \"$esc_path\""
        echo "        }"

        echo "    }"
        echo ""
    done

    # Overview tab: live dashboard of all worktrees + management shell
    local esc_repo
    esc_repo=$(kdl_escape "$REPO_PATH")
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local esc_status_script
    esc_status_script=$(kdl_escape "$script_dir/worktree-status.sh")

    cat <<FOOTER
    // Overview tab — live worktree status dashboard
    tab name="Overview" color="cyan" {
        pane split_direction="vertical" {
            pane command="watch" name="Worktree Status" size="60%" {
                args "-n" "2" "-c" "$esc_status_script" "$esc_repo"
            }
            pane name="worktree-mgmt" size="40%" {
                cwd "$esc_repo"
            }
        }
    }
}
FOOTER
}

LAYOUT_CONTENT=$(generate_layout)

# ---------------------------------------------------------------------------
# Output or launch
# ---------------------------------------------------------------------------
if $LAYOUT_ONLY; then
    echo "$LAYOUT_CONTENT"
    exit 0
fi

LAYOUT_FILE=$(mktemp /tmp/worktree-layout-XXXXXXXX)
CONFIG_FILE=$(mktemp /tmp/worktree-config-XXXXXXXX)
# Clean up temp files on exit (success or failure)
trap 'rm -f "$LAYOUT_FILE" "$CONFIG_FILE"' EXIT

echo "$LAYOUT_CONTENT" > "$LAYOUT_FILE"

# Session config: quit on close (don't leave detached sessions) + keybind overrides
cat > "$CONFIG_FILE" <<'CONFIG'
// When the terminal tab/window is closed, kill the session instead of detaching
on_force_close "quit"

keybinds {
    tab {
        bind "x" { SwitchToMode "normal"; }
    }
    shared_among "pane" "tmux" {
        bind "x" { SwitchToMode "normal"; }
    }
}
CONFIG

if [[ -n "${ZELLIJ_SESSION_NAME:-}" ]]; then
    echo "Error: already inside Zellij session '$ZELLIJ_SESSION_NAME'."
    echo "Run this from outside Zellij, or detach first (Ctrl+o, d)."
    exit 1
fi

# Kill existing session with the same name if it exists
if zellij list-sessions 2>/dev/null | grep -qw "$SESSION_NAME"; then
    echo "Killing existing Zellij session: $SESSION_NAME"
    zellij kill-session "$SESSION_NAME" 2>/dev/null || true
    sleep 0.5
fi

echo "Launching Zellij workspace: $SESSION_NAME"
echo ""
echo "  Tabs:"
for i in "${!WT_PATHS[@]}"; do
    name=$(tab_name "${WT_BRANCHES[$i]}" "${WT_HEADS[$i]}")
    printf "    %-30s %s\n" "$name" "${WT_PATHS[$i]}"
done
echo "    Overview (live status)"
echo ""
echo "Attach later with: zellij attach $SESSION_NAME"
echo ""

zellij --config "$CONFIG_FILE" --new-session-with-layout "$LAYOUT_FILE" --session "$SESSION_NAME"
