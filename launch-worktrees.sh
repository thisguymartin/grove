#!/usr/bin/env bash
# Launch a Zellij workspace with one tab per git worktree.
#
# Usage:
#   ./launch-worktrees.sh                  # Use current repo
#   ./launch-worktrees.sh /path/to/repo    # Explicit repo path
#   ./launch-worktrees.sh --layout-only    # Print KDL to stdout (no launch)
#   ./launch-worktrees.sh --write-layout /tmp/grove.kdl .
#
# Each worktree gets its own Zellij tab containing:
#   Left:   lazygit focused on that worktree (60%)
#   Middle: Workbench shell (30% of right column)
#   Right:  AI Agent (70% of right column) — right column is 40% total width
#
# A top tab-bar shows all worktree tabs for easy navigation.
# A final "Overview" tab shows stacked live dashboards across all worktrees.
#
# Options:
#   --ai <editor>    AI editor command (default: opencode, or set AI_EDITOR)
#
# Tab names come from the branch name (strips "refs/heads/").
# Detached HEADs use the short commit SHA as the tab name.
#
# Requirements: git, zellij
# Optional:     lazygit (falls back to a plain shell if not installed)
#
# Attach to an existing session later with:
#   zellij attach grove-<reponame>

set -euo pipefail

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
REPO_PATH=""
LAYOUT_ONLY=false
WRITE_LAYOUT_PATH=""
SESSION_NAME=""  # set after REPO_PATH is resolved below
AI_EDITOR="${AI_EDITOR:-opencode}"

# Tab color palette — cycles through these for each worktree tab
# Tab colors — cycles through these (cyan is reserved for the Overview tab)
TAB_COLORS=("green" "blue" "yellow" "orange")

# Colored dot emoji per tab — matches TAB_COLORS cycle
TAB_DOTS=("🟢" "🔵" "🟡" "🟠")

while [[ $# -gt 0 ]]; do
    case "$1" in
        --layout-only) LAYOUT_ONLY=true; shift ;;
        --write-layout)
            WRITE_LAYOUT_PATH="${2:?--write-layout requires an output path}"
            shift 2
            ;;
        --kill-all)
            echo "Killing all Zellij sessions..."
            zellij kill-all-sessions 2>/dev/null || true
            zellij delete-all-sessions 2>/dev/null || true
            echo "Done."
            exit 0
            ;;
        --ai)
            AI_EDITOR="${2:?--ai requires an editor name (e.g. claude, opencode, codex)}"
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
REPO_NAME="$(basename "$REPO_PATH")"
SESSION_NAME="grove-${REPO_NAME}"

if ! command -v zellij &>/dev/null && ! $LAYOUT_ONLY; then
    echo "Error: zellij is required. Install from https://zellij.dev"
    exit 1
fi

HAS_LAZYGIT=false
command -v lazygit &>/dev/null && HAS_LAZYGIT=true

HAS_GH=false
if command -v gh &>/dev/null && gh auth status &>/dev/null 2>&1; then
    HAS_GH=true
fi

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

# Ensure the main worktree (original clone) is always included
main_found=false
for p in "${WT_PATHS[@]}"; do
    if [[ "$p" == "$REPO_PATH" ]]; then
        main_found=true
        break
    fi
done

if ! $main_found; then
    # Detect default branch name (main or master)
    main_branch=$(git -C "$REPO_PATH" symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|refs/remotes/origin/||')
    if [[ -z "$main_branch" ]]; then
        # Fallback: check if main or master branch exists
        if git -C "$REPO_PATH" show-ref --verify --quiet refs/heads/main 2>/dev/null; then
            main_branch="main"
        elif git -C "$REPO_PATH" show-ref --verify --quiet refs/heads/master 2>/dev/null; then
            main_branch="master"
        else
            main_branch=$(git -C "$REPO_PATH" symbolic-ref HEAD 2>/dev/null | sed 's|refs/heads/||')
        fi
    fi
    main_head=$(git -C "$REPO_PATH" rev-parse HEAD 2>/dev/null || echo "")
    WT_PATHS=("$REPO_PATH" "${WT_PATHS[@]}")
    WT_BRANCHES=("refs/heads/$main_branch" "${WT_BRANCHES[@]}")
    WT_HEADS=("$main_head" "${WT_HEADS[@]}")
fi

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
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local template_file="$script_dir/layouts/workspace.kdl.template"
    local esc_repo esc_script_dir
    local tabs_file gh_panes_file

    if [[ ! -f "$template_file" ]]; then
        echo "Error: layout template not found at $template_file" >&2
        return 1
    fi

    esc_repo=$(kdl_escape "$REPO_PATH")
    esc_script_dir=$(kdl_escape "$script_dir")
    tabs_file=$(mktemp /tmp/grove-tabs-XXXXXXXX)
    gh_panes_file=$(mktemp /tmp/grove-gh-panes-XXXXXXXX)
    trap 'rm -f "$tabs_file" "$gh_panes_file"' RETURN

    if $HAS_GH; then
        {
            printf '                pane command="bash" name="PR Status" {\n'
            printf '                    args "-c" "while true; do _out=$(bash ./pr-status.sh \\\"%s\\\" 2>/dev/null); clear; printf '\''%%s'\'' \\\"$_out\\\"; sleep 60; done"\n' "$esc_repo"
            printf '                }\n'
            printf '                pane command="bash" name="CI / GitHub Actions" {\n'
            printf '                    args "-c" "while true; do _out=$(bash ./ci-status.sh \\\"%s\\\" 2>/dev/null); clear; printf '\''%%s'\'' \\\"$_out\\\"; sleep 60; done"\n' "$esc_repo"
            printf '                }\n'
        } >> "$gh_panes_file"
    fi

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
        local dot_index=$((i % ${#TAB_DOTS[@]}))
        local tab_dot="${TAB_DOTS[$dot_index]}"

        # Add bot emoji to non-main worktree tabs
        local tab_prefix="${tab_dot}"
        if [[ "$i" -gt 0 ]]; then
            tab_prefix="${tab_dot} 🤖"
        fi

        if [[ "$i" -eq 0 ]]; then
            printf '    tab name="%s %s" color="%s" focus=true {\n' "$tab_prefix" "$esc_name" "$tab_color" >> "$tabs_file"
        else
            printf '    tab name="%s %s" color="%s" {\n' "$tab_prefix" "$esc_name" "$tab_color" >> "$tabs_file"
        fi

        # THREE-COLUMN split: LazyGit (60%) | Workbench (12%) | AI Agent (28%)
        printf '        pane split_direction="vertical" {\n' >> "$tabs_file"

        # Left: lazygit (or plain shell if lazygit not installed)
        if $HAS_LAZYGIT; then
            printf '            pane command="lazygit" name="LazyGit" size="60%%" {\n' >> "$tabs_file"
            printf '                cwd "%s"\n' "$esc_path" >> "$tabs_file"
            printf '            }\n' >> "$tabs_file"
        else
            printf '            pane name="git: %s" size="60%%" {\n' "$esc_name" >> "$tabs_file"
            printf '                cwd "%s"\n' "$esc_path" >> "$tabs_file"
            printf '            }\n' >> "$tabs_file"
        fi

        # Right: Workbench (30%) | AI Agent (70%) — side by side
        printf '            pane split_direction="horizontal" size="40%%" {\n' >> "$tabs_file"

        printf '                pane name="Workbench" size="40%%" {\n' >> "$tabs_file"
        printf '                    cwd "%s"\n' "$esc_path" >> "$tabs_file"
        printf '                }\n' >> "$tabs_file"

        printf '                pane command="%s" name="AI Agent" size="60%%" {\n' "$esc_ai" >> "$tabs_file"
        printf '                    cwd "%s"\n' "$esc_path" >> "$tabs_file"
        if [[ "$i" -eq 0 ]]; then
            printf '                    focus true\n' >> "$tabs_file"
        fi
        printf '                }\n' >> "$tabs_file"

        printf '            }\n' >> "$tabs_file"

        printf '        }\n' >> "$tabs_file"

        printf '    }\n\n' >> "$tabs_file"
    done

    python3 - "$template_file" "$tabs_file" "$gh_panes_file" "$esc_script_dir" "$esc_repo" <<'PY'
import pathlib
import sys

template_path = pathlib.Path(sys.argv[1])
tabs_path = pathlib.Path(sys.argv[2])
gh_panes_path = pathlib.Path(sys.argv[3])
grove_dir = sys.argv[4]
repo_path = sys.argv[5]

template = template_path.read_text()
tabs = tabs_path.read_text()
gh_panes = gh_panes_path.read_text()
rendered = template.replace("{{GROVE_INSTALL_DIR}}", grove_dir)
rendered = rendered.replace("{{REPO_PATH}}", repo_path)
rendered = rendered.replace("    // {{WORKTREE_TABS}}", tabs.rstrip())
rendered = rendered.replace("                // {{GITHUB_STACK_PANES}}", gh_panes.rstrip())
print(rendered)
PY
}

LAYOUT_CONTENT=$(generate_layout)

# ---------------------------------------------------------------------------
# Output or launch
# ---------------------------------------------------------------------------
if $LAYOUT_ONLY; then
    echo "$LAYOUT_CONTENT"
    exit 0
fi

if [[ -n "$WRITE_LAYOUT_PATH" ]]; then
    printf '%s\n' "$LAYOUT_CONTENT" > "$WRITE_LAYOUT_PATH"
    echo "Wrote rendered layout to $WRITE_LAYOUT_PATH"
    exit 0
fi

LAYOUT_FILE="/tmp/grove-layout-${REPO_NAME}.kdl"

echo "$LAYOUT_CONTENT" > "$LAYOUT_FILE"

ZELLIJ_SESSION_NAME="${ZELLIJ_SESSION_NAME:-}"
if [[ -n "$ZELLIJ_SESSION_NAME" ]] || [[ "${ZELLIJ:-}" == "0" ]]; then
    echo ""
    echo "Error: already inside Zellij session '${ZELLIJ_SESSION_NAME:-unknown}'."
    echo "Run this from outside Zellij, or detach first (Ctrl+o, d)."
    exit 1
fi

# ---------------------------------------------------------------------------
# Session cleanup helper — reliably kill and delete a Zellij session
# Usage: cleanup_zellij_session <session_name> <timeout_seconds>
# ---------------------------------------------------------------------------
cleanup_zellij_session() {
    local session="$1"
    local timeout="${2:-5}"

    # Strip ANSI color codes before matching — zellij list-sessions wraps names in escape sequences
    if ! zellij list-sessions 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g' | grep -q "^${session}"; then
        return 0
    fi

    echo "Cleaning up existing Zellij session: $session"
    zellij kill-session "$session" 2>/dev/null || true
    zellij delete-session "$session" 2>/dev/null || true

    # Poll until session is gone or timeout
    local elapsed=0
    while zellij list-sessions 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g' | grep -q "^${session}"; do
        if (( elapsed >= timeout )); then
            echo "Warning: session '$session' still present after ${timeout}s, force deleting..."
            zellij delete-session "$session" --force 2>/dev/null || true
            break
        fi
        sleep 0.5
        elapsed=$((elapsed + 1))
    done
}

cleanup_zellij_session "$SESSION_NAME" 5

echo "Launching Zellij workspace: $SESSION_NAME"
echo ""
echo "  Tabs:"
for i in "${!WT_PATHS[@]}"; do
    name=$(tab_name "${WT_BRANCHES[$i]}" "${WT_HEADS[$i]}")
    printf "    %-30s %s\n" "$name" "${WT_PATHS[$i]}"
done
echo "    Overview (live status)"
echo ""
echo "To reattach later:"
echo "  zellij list-sessions    # Find the session name"
echo "  zellij attach <name>    # Reattach to it"
echo ""

export AI_EDITOR
exec zellij --new-session-with-layout "$LAYOUT_FILE" --session "$SESSION_NAME"
