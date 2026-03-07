#!/usr/bin/env bash
# Launch a Zellij workspace with one tab per git worktree.
#
# Usage:
#   ./launch-worktrees.sh                  # Use current repo
#   ./launch-worktrees.sh /path/to/repo    # Explicit repo path
#   ./launch-worktrees.sh --layout-only    # Print KDL to stdout (no launch)
#
# Each worktree gets its own Zellij tab containing:
#   Left:   lazygit focused on that worktree (60%)
#   Middle: Workbench shell (30% of right column)
#   Right:  AI Agent (70% of right column) — right column is 40% total width
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
#   zellij attach grove-<reponame>

set -euo pipefail

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
REPO_PATH=""
LAYOUT_ONLY=false
SESSION_NAME=""  # set after REPO_PATH is resolved below
AI_EDITOR="${AI_EDITOR:-claude}"
SKIP_PRUNE=false

# Tab color palette — cycles through these for each worktree tab
# Tab colors — cycles through these (cyan is reserved for the Overview tab)
TAB_COLORS=("green" "blue" "yellow" "orange")

# Colored dot emoji per tab — matches TAB_COLORS cycle
TAB_DOTS=("🟢" "🔵" "🟡" "🟠")

while [[ $# -gt 0 ]]; do
    case "$1" in
        --layout-only) LAYOUT_ONLY=true; shift ;;
        --kill-all)
            echo "Killing all Zellij sessions..."
            zellij kill-all-sessions 2>/dev/null || true
            zellij delete-all-sessions 2>/dev/null || true
            echo "Done."
            shift
            ;;
        --ai)
            AI_EDITOR="${2:?--ai requires an editor name (e.g. claude, opencode)}"
            shift 2
            ;;
        --skip-prune) SKIP_PRUNE=true; shift ;;
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

# ---------------------------------------------------------------------------
# Smart AI editor fallback
# ---------------------------------------------------------------------------
resolve_ai_editor() {
    local requested="$1"
    if command -v "$requested" &>/dev/null; then
        echo "$requested"
        return
    fi

    local fallback_order=("claude" "gemini" "opencode")
    for candidate in "${fallback_order[@]}"; do
        if [[ "$candidate" != "$requested" ]] && command -v "$candidate" &>/dev/null; then
            echo -e "\033[33m$requested not found, falling back to $candidate\033[0m" >&2
            echo "$candidate"
            return
        fi
    done

    # No AI agent found at all
    echo -e "\033[33mNo AI agent found (tried: $requested, ${fallback_order[*]}). AI pane will open a shell.\033[0m" >&2
    echo "bash"
}

AI_EDITOR=$(resolve_ai_editor "$AI_EDITOR")

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

# ---------------------------------------------------------------------------
# Auto-prune merged worktree branches
# ---------------------------------------------------------------------------
if ! $SKIP_PRUNE && [[ ${#WT_PATHS[@]} -gt 1 ]]; then
    # Detect default branch
    prune_base=""
    if git -C "$REPO_PATH" show-ref --verify --quiet refs/heads/main 2>/dev/null; then
        prune_base="main"
    elif git -C "$REPO_PATH" show-ref --verify --quiet refs/heads/master 2>/dev/null; then
        prune_base="master"
    fi

    if [[ -n "$prune_base" ]]; then
        merged_branches=$(git -C "$REPO_PATH" branch --merged "$prune_base" 2>/dev/null | grep -v "^\*" | sed 's/^  //' | grep -v "^${prune_base}$" || true)
        merged_wts=()
        merged_paths=()

        for i in "${!WT_PATHS[@]}"; do
            [[ "$i" -eq 0 ]] && continue  # skip main worktree
            local_branch="${WT_BRANCHES[$i]#refs/heads/}"
            if echo "$merged_branches" | grep -qx "$local_branch" 2>/dev/null; then
                merged_wts+=("$local_branch")
                merged_paths+=("${WT_PATHS[$i]}")
            fi
        done

        if [[ ${#merged_wts[@]} -gt 0 ]]; then
            echo -e "\033[33mFound ${#merged_wts[@]} worktree(s) with branches already merged into $prune_base:\033[0m"
            for b in "${merged_wts[@]}"; do
                echo "  - $b"
            done
            read -r -p "Prune these merged worktrees? [y/N] " answer
            if [[ "$answer" =~ ^[Yy]$ ]]; then
                for p in "${merged_paths[@]}"; do
                    echo "  Removing $p"
                    git -C "$REPO_PATH" worktree remove --force "$p" 2>/dev/null || true
                done
                # Re-parse worktrees after pruning
                WT_PATHS=(); WT_BRANCHES=(); WT_HEADS=()
                parse_worktrees
                # Re-add main if needed
                main_found=false
                for p in "${WT_PATHS[@]}"; do
                    [[ "$p" == "$REPO_PATH" ]] && main_found=true && break
                done
                if ! $main_found; then
                    WT_PATHS=("$REPO_PATH" "${WT_PATHS[@]}")
                    WT_BRANCHES=("refs/heads/$prune_base" "${WT_BRANCHES[@]}")
                    main_head=$(git -C "$REPO_PATH" rev-parse HEAD 2>/dev/null || echo "")
                    WT_HEADS=("$main_head" "${WT_HEADS[@]}")
                fi
            fi
        fi
    fi
fi

if [[ ${#WT_PATHS[@]} -eq 0 ]]; then
    echo "Error: no worktrees found in $REPO_PATH"
    exit 1
fi

# ---------------------------------------------------------------------------
# Mochi manifest detection
# ---------------------------------------------------------------------------
MOCHI_MANIFEST="$REPO_PATH/.mochi_manifest.json"
HAS_MOCHI=false
declare -A MOCHI_SLUGS  # branch → slug mapping for Mochi-managed worktrees

if [[ -f "$MOCHI_MANIFEST" ]] && command -v jq &>/dev/null; then
    HAS_MOCHI=true
    while IFS='=' read -r branch slug; do
        MOCHI_SLUGS["$branch"]="$slug"
    done < <(jq -r 'to_entries[] | "\(.value.branch)=\(.key)"' "$MOCHI_MANIFEST" 2>/dev/null || true)
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

# Check if a worktree branch is managed by Mochi
is_mochi_worktree() {
    local branch="$1"
    local short="${branch#refs/heads/}"
    [[ -n "${MOCHI_SLUGS[$short]+x}" ]]
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

    # Overview tab: live dashboard of all worktrees + management shell
    local esc_repo
    esc_repo=$(kdl_escape "$REPO_PATH")
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local esc_status_script
    esc_status_script=$(kdl_escape "$script_dir/worktree-status.sh")
    local esc_ai_status_script
    esc_ai_status_script=$(kdl_escape "$script_dir/ai-status.sh")
    local esc_pr_status_script
    esc_pr_status_script=$(kdl_escape "$script_dir/pr-status.sh")
    local esc_resource_monitor_script
    esc_resource_monitor_script=$(kdl_escape "$script_dir/resource-monitor.sh")

    local esc_mochi_status_script
    esc_mochi_status_script=$(kdl_escape "$script_dir/mochi-status.sh")

    cat <<OVERVIEW
    // Overview tab — live project dashboards
    tab name="📊 Overview" color="cyan" {
        pane split_direction="vertical" size="70%" {
            pane command="bash" name="Worktree Status" size="40%" {
                args "-c" "while true; do _out=\$(\"$esc_status_script\" \"$esc_repo\" 2>/dev/null); clear; printf '%s' \"\$_out\"; sleep 15; done"
            }
            pane command="bash" name="AI Status" size="30%" {
                args "-c" "while true; do _out=\$(\"$esc_ai_status_script\" 2>/dev/null); clear; printf '%s' \"\$_out\"; sleep 30; done"
            }
            pane command="bash" name="PR Status" size="30%" {
                args "-c" "while true; do _out=\$(\"$esc_pr_status_script\" \"$esc_repo\" 2>/dev/null); clear; printf '%s' \"\$_out\"; sleep 60; done"
            }
        }
        pane split_direction="horizontal" size="30%" {
            pane command="bash" name="Resources" size="$($HAS_MOCHI && echo '50%' || echo '100%')" {
                args "-c" "while true; do _out=\$(\"$esc_resource_monitor_script\" 2>/dev/null); clear; printf '%s' \"\$_out\"; sleep 5; done"
            }
OVERVIEW

    if $HAS_MOCHI; then
        cat <<MOCHI_PANE
            pane command="bash" name="Mochi Tasks" size="50%" {
                args "-c" "while true; do _out=\$(\"$esc_mochi_status_script\" \"$esc_repo\" 2>/dev/null); clear; printf '%s' \"\$_out\"; sleep 10; done"
            }
MOCHI_PANE
    fi

    cat <<OVERVIEW_CLOSE
        }
    }

OVERVIEW_CLOSE

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

        # Add bot emoji to non-main worktree tabs; [M] prefix for Mochi-managed
        local tab_prefix="${tab_dot}"
        if [[ "$i" -gt 0 ]]; then
            tab_prefix="${tab_dot} 🤖"
        fi
        if $HAS_MOCHI && is_mochi_worktree "$branch"; then
            tab_prefix="[M] ${tab_prefix}"
        fi

        if [[ "$i" -eq 0 ]]; then
            echo "    tab name=\"${tab_prefix} ${esc_name}\" color=\"$tab_color\" focus=true {"
        else
            echo "    tab name=\"${tab_prefix} ${esc_name}\" color=\"$tab_color\" {"
        fi

        # THREE-COLUMN split: LazyGit (60%) | Workbench (12%) | AI Agent (28%)
        echo "        pane split_direction=\"vertical\" {"

        # Left: lazygit (or plain shell if lazygit not installed)
        if $HAS_LAZYGIT; then
            echo "            pane command=\"lazygit\" name=\"LazyGit\" size=\"60%\" {"
            echo "                cwd \"$esc_path\""
            echo "            }"
        else
            echo "            pane name=\"git: $esc_name\" size=\"60%\" {"
            echo "                cwd \"$esc_path\""
            echo "            }"
        fi

        # Right: Workbench (30%) | AI Agent (70%) — side by side
        echo "            pane split_direction=\"horizontal\" size=\"40%\" {"

        echo "                pane name=\"Workbench\" size=\"40%\" {"
        echo "                    cwd \"$esc_path\""
        echo "                }"

        echo "                pane command=\"$esc_ai\" name=\"AI Agent\" size=\"60%\" {"
        echo "                    cwd \"$esc_path\""
        if [[ "$i" -eq 0 ]]; then
            echo "                    focus true"
        fi
        echo "                }"

        echo "            }"

        echo "        }"

        echo "    }"
        echo ""
    done

    cat <<'FOOTER'
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

# Kill/delete existing session with the same name if it exists
if zellij list-sessions 2>/dev/null | grep -qw "$SESSION_NAME"; then
    echo "Cleaning up existing Zellij session: $SESSION_NAME"
    zellij kill-session "$SESSION_NAME" 2>/dev/null || true
    zellij delete-session "$SESSION_NAME" 2>/dev/null || true
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
