#!/usr/bin/env bash
# Git Worktree Management Toolkit
#
# A set of commands for managing git worktrees with a consistent directory
# structure. Worktrees are created under a sibling "worktrees/" directory
# next to your main repo clone.
#
# Usage:
#   git-worktree.sh add <branch>            # Add worktree for an existing remote branch
#   git-worktree.sh new <branch>            # Create a new branch and worktree
#   git-worktree.sh rm  <branch>            # Remove a worktree (and optionally its branch)
#   git-worktree.sh ls                      # List all worktrees
#   git-worktree.sh prune                   # Remove worktrees whose branches are merged/gone
#   git-worktree.sh tab                     # Launch Zellij with a tab per worktree
#   git-worktree.sh tab --layout-only       # Print the generated Zellij layout to stdout
#
# Environment:
#   GWT_BASE_BRANCH  - Base branch for prune comparison (default: main)
#   GWT_WORKTREE_DIR - Override the worktree parent directory

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ─── Helpers ──────────────────────────────────────────────────────────────────

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || {
    echo "Error: not inside a git repository."
    exit 1
}

REPO_NAME="$(basename "$REPO_ROOT")"
PARENT_DIR="$(dirname "$REPO_ROOT")"
WORKTREE_DIR="${GWT_WORKTREE_DIR:-${PARENT_DIR}/worktrees/${REPO_NAME}}"
BASE_BRANCH="${GWT_BASE_BRANCH:-main}"

ensure_worktree_dir() {
    if [[ ! -d "$WORKTREE_DIR" ]]; then
        mkdir -p "$WORKTREE_DIR"
    fi
}

# Print the worktree path for a branch (empty if none).
# Usage: resolve_worktree_path <branch>
resolve_worktree_path() {
    local branch="$1"
    git worktree list --porcelain | awk -v br="refs/heads/$branch" '
        /^worktree / { wt = substr($0, 10) }
        /^branch /   { if (substr($0, 8) == br) print wt }
    '
}

# Resolve the base branch: $GWT_BASE_BRANCH, else origin/HEAD, else "main".
# Usage: base=$(detect_base_branch)
detect_base_branch() {
    local default_base
    default_base=$(git symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null \
        | sed 's@^origin/@@' || true)
    echo "${GWT_BASE_BRANCH:-${default_base:-main}}"
}

# Name of the Zellij session for this repo (current session if inside one).
# Usage: session=$(grove_session)
grove_session() {
    echo "${ZELLIJ_SESSION_NAME:-grove-${REPO_NAME}}"
}

# ─── Zellij Integration ───────────────────────────────────────────────────────

# Generate a standalone KDL layout for a single worktree tab
# Usage: generate_single_tab_kdl <wt_path> <branch> <ai_editor>
generate_single_tab_kdl() {
    local wt_path="$1"
    local branch="$2"
    local ai_editor="${3:-opencode}"

    cat <<EOF
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

    tab name="${branch}" color="magenta" {
        pane split_direction="vertical" {
            pane command="lazygit" name="LazyGit" size="60%" {
                cwd "${wt_path}"
            }
            pane split_direction="horizontal" size="40%" {
                pane name="Workbench" size="40%" {
                    cwd "${wt_path}"
                }
                pane command="${ai_editor}" name="AI Agent" size="60%" {
                    cwd "${wt_path}"
                    focus true
                }
            }
        }
    }
}
EOF
}

# Dynamically add a tab for the new worktree to a running Zellij session.
# Works both inside a Zellij session and from an external terminal.
# Usage: maybe_add_zellij_tab <wt_path> <branch>
maybe_add_zellij_tab() {
    local wt_path="$1"
    local branch="$2"

    # Determine target session: use current session if inside Zellij,
    # otherwise look for the grove session for this repo.
    local target_session="${ZELLIJ_SESSION_NAME:-}"

    if [[ -z "$target_session" ]]; then
        local grove_session="grove-${REPO_NAME}"
        if zellij list-sessions 2>/dev/null | grep -q "^${grove_session}"; then
            target_session="$grove_session"
        else
            return 0
        fi
    fi

    local ai_editor="${AI_EDITOR:-opencode}"
    local layout_file
    layout_file=$(mktemp /tmp/gwt-single-tab-XXXXXXXX.kdl)

    generate_single_tab_kdl "$wt_path" "$branch" "$ai_editor" > "$layout_file"
    echo "Adding Zellij tab for '$branch'..."

    if [[ -n "${ZELLIJ_SESSION_NAME:-}" ]]; then
        # Inside Zellij — use action directly
        zellij action new-tab --layout "$layout_file" 2>/dev/null || {
            echo "Warning: could not add Zellij tab."
        }
    else
        # Outside Zellij — target the session by name
        zellij --session "$target_session" action new-tab --layout "$layout_file" 2>/dev/null || {
            echo "Warning: could not add Zellij tab to session '$target_session'."
        }
    fi
    rm -f "$layout_file"
}

# Reliably kill and delete a Zellij session
# Usage: cleanup_zellij_session <session_name> <timeout_seconds>
cleanup_zellij_session() {
    local session="$1"
    local timeout="${2:-5}"

    if ! zellij list-sessions 2>/dev/null | grep -q "^${session}"; then
        return 0
    fi

    echo "Cleaning up existing Zellij session: $session"
    zellij kill-session "$session" 2>/dev/null || true
    zellij delete-session "$session" 2>/dev/null || true

    local elapsed=0
    while zellij list-sessions 2>/dev/null | grep -q "^${session}"; do
        if (( elapsed >= timeout )); then
            echo "Warning: session '$session' still present after ${timeout}s, force deleting..."
            zellij delete-session "$session" --force 2>/dev/null || true
            break
        fi
        sleep 0.5
        elapsed=$((elapsed + 1))
    done
}

# ─── Commands ─────────────────────────────────────────────────────────────────

cmd_add() {
    local branch="${1:?Usage: git-worktree.sh add <branch>}"
    local target="${WORKTREE_DIR}/${branch}"

    ensure_worktree_dir

    if [[ -d "$target" ]]; then
        echo "Worktree already exists at $target"
        exit 0
    fi

    # Fetch the branch from origin if it exists remotely
    git fetch origin "$branch" 2>/dev/null || true
    git worktree add "$target" "$branch"
    echo "Worktree added: $target (branch: $branch)"
    maybe_add_zellij_tab "$target" "$branch"
}

cmd_new() {
    local branch="${1:?Usage: git-worktree.sh new <branch>}"
    local target="${WORKTREE_DIR}/${branch}"

    ensure_worktree_dir

    if [[ -d "$target" ]]; then
        echo "Worktree already exists at $target"
        exit 0
    fi

    git worktree add "$target" -b "$branch"
    echo "Worktree created: $target (new branch: $branch)"
    maybe_add_zellij_tab "$target" "$branch"
}

cmd_rm() {
    local branch="${1:?Usage: git-worktree.sh rm <branch>}"

    # Find the worktree path from git's own registry by branch name
    local target
    target=$(git worktree list --porcelain | awk '
        /^worktree / { path=substr($0, 10) }
        /^branch refs\/heads\// { b=substr($0, 8); sub(/^refs\/heads\//, "", b); if (b==branch) print path }
    ' branch="$branch")

    # Fallback: check the conventional location
    if [[ -z "$target" ]]; then
        target="${WORKTREE_DIR}/${branch}"
    fi

    if [[ ! -d "$target" ]]; then
        echo "No worktree found for branch '$branch'"
        exit 1
    fi

    git worktree remove --force "$target"
    echo "Worktree removed: $target"

    # Offer to delete the branch
    if git show-ref --verify --quiet "refs/heads/$branch"; then
        read -rp "Delete local branch '$branch'? [y/N] " answer
        if [[ "$answer" =~ ^[Yy]$ ]]; then
            git branch -D "$branch"
            echo "Branch '$branch' deleted."
        fi
    fi
}

cmd_ls() {
    echo "Git Worktrees for ${REPO_NAME}:"
    echo "─────────────────────────────────────────"
    git worktree list --porcelain | awk '
        /^worktree / { wt = substr($0, 10) }
        /^branch /   { br = substr($0, 8); sub(/^refs\/heads\//, "", br) }
        $1 == "HEAD"     { head = $2 }
        $1 == "detached" { br = "(detached)" }
        $1 == "locked"   { locked = " [locked]" }
        /^$/ {
            if (wt != "") {
                printf "  %-50s %s%s\n", wt, br, locked
            }
            wt = br = head = locked = ""
        }
        END {
            if (wt != "") {
                printf "  %-50s %s%s\n", wt, br, locked
            }
        }
    '
}

cmd_prune() {
    echo "Pruning merged/stale worktrees (base: $BASE_BRANCH)..."

    # First, let git clean up any broken worktree references
    git worktree prune

    # Fetch to get latest remote state
    git fetch -p origin 2>/dev/null || true

    local pruned=0

    while IFS=$'\t' read -r wt br; do
        # Skip the main worktree
        if [[ "$wt" == "$REPO_ROOT" ]]; then
            continue
        fi

        # Skip if branch matches the base branch
        if [[ "$br" == "$BASE_BRANCH" ]]; then
            continue
        fi

        # Check if the branch has been merged into the base branch
        if git merge-base --is-ancestor "refs/heads/$br" "refs/heads/$BASE_BRANCH" 2>/dev/null; then
            echo "  Removing (merged): $wt [$br]"
            git worktree remove --force "$wt"
            pruned=$((pruned + 1))
            continue
        fi

        # Check if the remote tracking branch is gone
        if ! git show-ref --verify --quiet "refs/remotes/origin/$br" 2>/dev/null; then
            # Branch has no remote tracking — check if it's been squash-merged
            # by comparing patch IDs
            local branch_patch
            branch_patch=$(git diff "$BASE_BRANCH...$br" 2>/dev/null | git patch-id --stable 2>/dev/null | awk '{print $1}' | head -n1) || true

            if [[ -z "$branch_patch" ]]; then
                continue
            fi

            local found=""
            while IFS= read -r commit; do
                local commit_patch
                commit_patch=$(git diff "$commit^..$commit" 2>/dev/null | git patch-id --stable 2>/dev/null | awk '{print $1}' | head -n1) || true
                if [[ "$commit_patch" == "$branch_patch" ]]; then
                    found="$commit"
                    break
                fi
            done < <(git log --format="%H" "$BASE_BRANCH" --since="4 weeks ago" 2>/dev/null)

            if [[ -n "$found" ]]; then
                echo "  Removing (squash-merged): $wt [$br]"
                git worktree remove --force "$wt"
                pruned=$((pruned + 1))
            fi
        fi
    done < <(git worktree list --porcelain | awk '
        /^worktree / { wt = substr($0, 10) }
        /^branch /   { br = substr($0, 8); sub(/^refs\/heads\//, "", br) }
        /^locked/    { locked = 1 }
        /^$/ {
            if (wt != "" && locked != 1) {
                print wt "\t" br
            }
            wt = br = ""; locked = 0
        }
        END {
            if (wt != "" && locked != 1) {
                print wt "\t" br
            }
        }
    ')

    if [[ "$pruned" -eq 0 ]]; then
        echo "  Nothing to prune."
    else
        echo "  Pruned $pruned worktree(s)."
    fi
}

cmd_tab() {
    local layout_only=false
    if [[ "${1:-}" == "--layout-only" ]]; then
        layout_only=true
    fi

    # Collect worktree information
    local -a wt_paths=()
    local -a wt_branches=()

    while IFS=$'\t' read -r wt br; do
        wt_paths+=("$wt")
        wt_branches+=("$br")
    done < <(
        git worktree list --porcelain | awk '
            /^worktree / { wt = substr($0, 10) }
            /^branch /   { br = substr($0, 8); sub(/^refs\/heads\//, "", br) }
            $1 == "detached" { br = "(detached)" }
            /^$/ {
                if (wt != "") print wt "\t" br
                wt = br = ""
            }
            END {
                if (wt != "") print wt "\t" br
            }
        '
    )

    if [[ ${#wt_paths[@]} -eq 0 ]]; then
        echo "No worktrees found."
        exit 1
    fi

    # Generate a KDL layout with one tab per worktree
    local layout
    layout=$(generate_tab_layout "${wt_paths[@]}" -- "${wt_branches[@]}")

    if $layout_only; then
        echo "$layout"
        exit 0
    fi

    local layout_file
    layout_file=$(mktemp /tmp/gwt-tabs-XXXXXXXX)
    trap 'rm -f "'"$layout_file"'"' EXIT
    echo "$layout" > "$layout_file"

    local session_name="grove-${REPO_NAME}"

    echo "Launching Zellij with ${#wt_paths[@]} worktree tab(s)..."
    for i in "${!wt_paths[@]}"; do
        echo "  [Tab $((i+1))] ${wt_branches[$i]} -> ${wt_paths[$i]}"
    done
    echo ""
    echo "Session: $session_name"
    echo "Tip: Use Alt+Left/Right to switch between worktree tabs"
    echo ""

    ZELLIJ_SESSION_NAME="${ZELLIJ_SESSION_NAME:-}"
    if [[ -n "$ZELLIJ_SESSION_NAME" ]] || [[ "${ZELLIJ:-}" == "0" ]]; then
        echo ""
        echo "Error: already inside Zellij session '${ZELLIJ_SESSION_NAME:-unknown}'."
        echo "Detach first (Ctrl+o, d), then re-run this command."
        rm -f "$layout_file"
        exit 1
    fi

    cleanup_zellij_session "$session_name" 5

    zellij --new-session-with-layout "$layout_file" --session "$session_name"
}

generate_tab_layout() {
    # Parse args: paths... -- branches...
    local -a paths=()
    local -a branches=()
    local parsing_branches=false

    for arg in "$@"; do
        if [[ "$arg" == "--" ]]; then
            parsing_branches=true
            continue
        fi
        if $parsing_branches; then
            branches+=("$arg")
        else
            paths+=("$arg")
        fi
    done

    # Start layout
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

    # AI editor (default: opencode, override with AI_EDITOR env var)
    local ai_editor="${AI_EDITOR:-opencode}"

    # Tab color palette — cycles through these for each worktree tab
    # 15 visually distinct colors (cyan is reserved for the Overview tab)
    local -a tab_colors=(
        "green" "blue" "yellow" "magenta" "orange" "red"
        "#d75fd7" "#00afd7" "#5fd700" "#af87ff"
        "#d7af5f" "#ff5f87" "#00d7af" "#5f87d7" "#d78700"
    )

    # One tab per worktree
    for i in "${!paths[@]}"; do
        local path="${paths[$i]}"
        local branch="${branches[$i]}"
        local color_index=$((i % ${#tab_colors[@]}))
        local tab_color="${tab_colors[$color_index]}"

        cat <<EOF

    tab name="${branch}" color="${tab_color}" {
        // TOP: LazyGit + AI Agent side by side
        pane split_direction="vertical" size="70%" {
            pane command="lazygit" name="LazyGit" {
                cwd "${path}"
            }
            pane command="${ai_editor}" name="AI Agent" {
                cwd "${path}"
                focus true
            }
        }
        // BOTTOM: Workbench shell
        pane name="Workbench" {
            cwd "${path}"
        }
    }
EOF
    done

    # Overview tab: live dashboard of all worktrees
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

    cat <<FOOTER

    tab name="Overview" color="cyan" {
        pane split_direction="vertical" {
            pane command="watch" name="Worktree Status" size="60%" {
                args "-n" "2" "-c" "${script_dir}/worktree-status.sh" "${REPO_ROOT}"
            }
            pane name="worktree-mgmt" size="40%" {
                cwd "${REPO_ROOT}"
            }
        }
    }
}
FOOTER
}

# ─── New Commands ─────────────────────────────────────────────────────────────

# Print the path of a worktree by branch name.
# A subprocess can't change the parent shell's cwd — the `grove()` shell
# function captures this output and runs `cd` itself (see git-worktree-aliases.sh).
cmd_which() {
    local branch="${1:?Usage: git-worktree.sh which <branch>}"
    local wt_path
    wt_path=$(resolve_worktree_path "$branch")
    if [[ -z "$wt_path" ]]; then
        echo "No worktree found for branch '$branch'" >&2
        exit 1
    fi
    echo "$wt_path"
}

# Print the path of the main worktree (the original clone).
cmd_root() {
    git worktree list --porcelain | awk '/^worktree / { print substr($0, 10); exit }'
}

# Interactive worktree picker. Lists every worktree with the branch name in
# color followed by its path, lets the user choose one (fzf when available,
# else a numbered menu), and prints ONLY the chosen path to stdout. The
# `grove()` shell function captures that path and runs `cd` itself — a
# subprocess can't change the parent shell's cwd. All UI is drawn on the
# tty/stderr so the captured stdout stays a single clean path.
cmd_pick() {
    # branch<TAB>path rows (same porcelain parse as cmd_ls)
    local rows
    rows=$(git worktree list --porcelain | awk '
        /^worktree / { wt = substr($0, 10) }
        /^branch /   { br = substr($0, 8); sub(/^refs\/heads\//, "", br) }
        $1 == "detached" { br = "(detached)" }
        $1 == "locked"   { locked = " [locked]" }
        /^$/ {
            if (wt != "") printf "%s%s\t%s\n", br, locked, wt
            wt = br = locked = ""
        }
        END { if (wt != "") printf "%s%s\t%s\n", br, locked, wt }
    ')

    if [[ -z "$rows" ]]; then
        echo "No worktrees found." >&2
        exit 1
    fi

    # Colors — skip when stderr is not a terminal or NO_COLOR is set.
    local CYAN='' DIM='' RESET=''
    if [[ -t 2 && -z "${NO_COLOR:-}" ]]; then
        CYAN=$'\033[1;36m'; DIM=$'\033[2m'; RESET=$'\033[0m'
    fi

    if command -v fzf >/dev/null 2>&1; then
        # Display = colored branch + dim path (field 1); a clean path is carried
        # in a tab-delimited field 2 that fzf hides but returns on selection.
        local selected
        selected=$(
            printf '%s\n' "$rows" \
            | awk -F'\t' -v c="$CYAN" -v d="$DIM" -v r="$RESET" \
                '{ printf "%s%-32s%s %s%s%s\t%s\n", c, $1, r, d, $2, r, $2 }' \
            | fzf --ansi --with-nth=1 --delimiter=$'\t' \
                  --prompt='worktree> ' \
                  --header='Select worktree (Enter to cd, Esc to cancel)'
        ) || exit 1
        [[ -n "$selected" ]] || exit 1
        printf '%s\n' "$selected" | awk -F'\t' '{ print $NF }'
    else
        # Numbered-menu fallback — all UI on stderr, chosen path on stdout.
        local -a paths=() branches=()
        local br wt
        while IFS=$'\t' read -r br wt; do
            [[ -n "$wt" ]] || continue
            branches+=("$br"); paths+=("$wt")
        done <<< "$rows"

        echo "Select a worktree:" >&2
        local i
        for i in "${!paths[@]}"; do
            printf '  %s%2d%s) %s%-32s%s %s%s%s\n' \
                "$CYAN" "$((i + 1))" "$RESET" \
                "$CYAN" "${branches[$i]}" "$RESET" \
                "$DIM" "${paths[$i]}" "$RESET" >&2
        done

        local choice
        read -r -p "#? " choice </dev/tty || exit 1
        [[ "$choice" =~ ^[0-9]+$ ]] || { echo "Invalid selection." >&2; exit 1; }
        local idx=$((choice - 1))
        if (( idx < 0 || idx >= ${#paths[@]} )); then
            echo "Selection out of range." >&2
            exit 1
        fi
        printf '%s\n' "${paths[$idx]}"
    fi
}

cmd_info() {
    local branch="${1:-$(git symbolic-ref --short HEAD 2>/dev/null)}"
    if [[ -z "$branch" ]]; then
        echo "Error: not on a branch and no branch specified"
        exit 1
    fi

    local wt_path="" head_sha=""
    while IFS= read -r line; do
        case "$line" in
            worktree\ *) wt_path="${line#worktree }" ;;
            HEAD\ *)     head_sha="${line#HEAD }" ;;
            branch\ *)
                if [[ "${line#branch refs/heads/}" == "$branch" ]]; then
                    break
                fi
                wt_path="" ; head_sha=""
                ;;
            "") wt_path="" ; head_sha="" ;;
        esac
    done < <(git worktree list --porcelain)

    if [[ -z "$wt_path" ]]; then
        echo "No worktree found for branch '$branch'"
        exit 1
    fi

    echo "Branch:  $branch"
    echo "Path:    $wt_path"
    echo "HEAD:    ${head_sha:0:10}"

    local upstream
    upstream=$(git -C "$wt_path" rev-parse --abbrev-ref "@{upstream}" 2>/dev/null || true)
    if [[ -n "$upstream" ]]; then
        local ab
        ab=$(git -C "$wt_path" rev-list --left-right --count "$branch...$upstream" 2>/dev/null || true)
        if [[ -n "$ab" ]]; then
            local ahead behind
            ahead=$(echo "$ab" | awk '{print $1}')
            behind=$(echo "$ab" | awk '{print $2}')
            echo "Remote:  $upstream (ahead $ahead, behind $behind)"
        fi
    else
        echo "Remote:  (no upstream)"
    fi

    local status
    status=$(git -C "$wt_path" status --porcelain 2>/dev/null)
    if [[ -n "$status" ]]; then
        local count
        count=$(echo "$status" | wc -l | tr -d ' ')
        echo "Status:  dirty ($count changed file(s))"
    else
        echo "Status:  clean"
    fi
}

cmd_diff() {
    local branch="${1:-$(git symbolic-ref --short HEAD 2>/dev/null)}"
    if [[ -z "$branch" ]]; then
        echo "Error: not on a branch and no branch specified"
        exit 1
    fi

    local base
    base=$(detect_base_branch)

    echo "Diff: $branch vs $base"
    echo "─────────────────────────────────────────"
    git diff --stat "$base...$branch"
}

cmd_rename() {
    local old="${1:?Usage: git-worktree.sh rename <old-branch> <new-branch>}"
    local new="${2:?Usage: git-worktree.sh rename <old-branch> <new-branch>}"

    if ! git show-ref --verify --quiet "refs/heads/$old"; then
        echo "Error: branch '$old' does not exist"
        exit 1
    fi

    git branch -m "$old" "$new"
    echo "Branch renamed: $old -> $new"

    local wt_path
    wt_path=$(resolve_worktree_path "$new")
    if [[ -n "$wt_path" ]]; then
        echo "Note: worktree path is still: $wt_path"
        echo "  The directory was not renamed."
    fi
}

cmd_lock() {
    local path="${1:?Usage: git-worktree.sh lock <path>}"
    git worktree lock "$path"
    echo "Worktree locked: $path"
}

cmd_unlock() {
    local path="${1:?Usage: git-worktree.sh unlock <path>}"
    git worktree unlock "$path"
    echo "Worktree unlocked: $path"
}

# Resolve a branch to a worktree path or exit with an error.
# Usage: wt=$(require_worktree_path <branch>)
require_worktree_path() {
    local branch="${1:?branch required}"
    local wt_path
    wt_path=$(resolve_worktree_path "$branch")
    if [[ -z "$wt_path" ]]; then
        echo "No worktree found for branch '$branch'" >&2
        exit 1
    fi
    echo "$wt_path"
}

# Drop a leading "--" separator from the argument list, if present.
# Usage: strip_dashdash "$@"; set -- "${STRIPPED_ARGS[@]}"
strip_dashdash() {
    STRIPPED_ARGS=("$@")
    if [[ "${1:-}" == "--" ]]; then
        STRIPPED_ARGS=("${@:2}")
    fi
}

# Run a command inside a single worktree's directory.
# Usage: cmd_run <branch> [--] <cmd> [args...]
cmd_run() {
    local branch="${1:?Usage: git-worktree.sh run <branch> [--] <cmd> [args...]}"
    shift
    strip_dashdash "$@"
    set -- "${STRIPPED_ARGS[@]}"
    if [[ $# -eq 0 ]]; then
        echo "Error: no command given" >&2
        echo "Usage: git-worktree.sh run <branch> [--] <cmd> [args...]" >&2
        exit 1
    fi
    local wt_path
    wt_path=$(require_worktree_path "$branch")
    (cd "$wt_path" && exec "$@")
}

# Run a command in EVERY worktree directory (fan-out).
# Usage: cmd_exec [--] <cmd> [args...]
cmd_exec() {
    strip_dashdash "$@"
    set -- "${STRIPPED_ARGS[@]}"
    if [[ $# -eq 0 ]]; then
        echo "Error: no command given" >&2
        echo "Usage: git-worktree.sh exec [--] <cmd> [args...]" >&2
        exit 1
    fi
    local wt_path
    while IFS= read -r wt_path; do
        [[ -z "$wt_path" ]] && continue
        echo "── ${wt_path} ──────────────────────────────"
        (cd "$wt_path" && "$@") || echo "  (command failed in $wt_path)"
    done < <(git worktree list --porcelain | awk '/^worktree / { print substr($0, 10) }')
}

# Fetch + rebase a branch onto its base branch. Refuses a dirty tree.
# Usage: cmd_sync [branch]
cmd_sync() {
    local branch="${1:-$(git symbolic-ref --short HEAD 2>/dev/null)}"
    if [[ -z "$branch" ]]; then
        echo "Error: not on a branch and no branch specified" >&2
        exit 1
    fi
    local wt_path
    wt_path=$(require_worktree_path "$branch")

    if [[ -n "$(git -C "$wt_path" status --porcelain)" ]]; then
        echo "Error: worktree for '$branch' has uncommitted changes. Commit or stash first." >&2
        exit 1
    fi

    local base
    base=$(detect_base_branch)
    echo "Syncing '$branch' onto 'origin/$base'..."
    git -C "$wt_path" fetch origin "$base"
    git -C "$wt_path" rebase "origin/$base"
}

# Open (or create) the branch's GitHub PR. Requires the gh CLI.
# Usage: cmd_pr [branch]
cmd_pr() {
    if ! command -v gh >/dev/null 2>&1; then
        echo "Error: 'gh' (GitHub CLI) is required for 'grove pr'. Install: https://cli.github.com" >&2
        exit 1
    fi
    local branch="${1:-$(git symbolic-ref --short HEAD 2>/dev/null)}"
    if [[ -z "$branch" ]]; then
        echo "Error: not on a branch and no branch specified" >&2
        exit 1
    fi
    local wt_path
    wt_path=$(require_worktree_path "$branch")

    if (cd "$wt_path" && gh pr view "$branch" --web) 2>/dev/null; then
        return 0
    fi
    echo "No existing PR for '$branch' — creating one..."
    (cd "$wt_path" && gh pr create --web --head "$branch")
}

# Move a worktree to a new directory.
# Usage: cmd_mv <branch> <new-path>
cmd_mv() {
    local branch="${1:?Usage: git-worktree.sh mv <branch> <new-path>}"
    local new_path="${2:?Usage: git-worktree.sh mv <branch> <new-path>}"
    local wt_path
    wt_path=$(require_worktree_path "$branch")
    git worktree move "$wt_path" "$new_path"
    echo "Worktree moved: $wt_path -> $new_path"
}

# Show git log of a branch vs its base branch.
# Usage: cmd_log [branch]
cmd_log() {
    local branch="${1:-$(git symbolic-ref --short HEAD 2>/dev/null)}"
    if [[ -z "$branch" ]]; then
        echo "Error: not on a branch and no branch specified" >&2
        exit 1
    fi
    local base
    base=$(detect_base_branch)
    echo "Log: $base..$branch"
    echo "─────────────────────────────────────────"
    git log --oneline --no-merges "$base..$branch"
}

# Open a worktree in your editor ($GROVE_EDITOR, else $EDITOR, else code).
# Usage: cmd_open <branch>
cmd_open() {
    local branch="${1:?Usage: git-worktree.sh open <branch>}"
    local wt_path
    wt_path=$(require_worktree_path "$branch")
    local editor="${GROVE_EDITOR:-${EDITOR:-code}}"
    "$editor" "$wt_path"
}

# Jump to a worktree's Zellij tab (or attach the session when outside Zellij).
# Tabs are named exactly by branch, so go-to-tab-name resolves directly.
# Usage: cmd_go <branch>
cmd_go() {
    local branch="${1:?Usage: git-worktree.sh go <branch>}"
    if [[ -n "${ZELLIJ:-}" ]]; then
        zellij action go-to-tab-name "$branch" || {
            echo "No Zellij tab named '$branch'. Run 'grove up' first, or 'grove agent $branch'." >&2
            exit 1
        }
    else
        local session
        session=$(grove_session)
        if ! zellij list-sessions 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g' | grep -q "^${session}"; then
            echo "No running Zellij session '$session'. Launch it with 'grove up'." >&2
            exit 1
        fi
        echo "Attaching to '$session' — switch to the '$branch' tab once inside (Alt+←/→)."
        zellij attach "$session"
    fi
}

# Open or focus an AI agent tab for a worktree.
# If the tab doesn't exist yet, create it (with optional AI editor override).
# Usage: cmd_agent <branch> [ai-editor]
cmd_agent() {
    local branch="${1:?Usage: git-worktree.sh agent <branch> [ai-editor]}"
    local ai_editor="${2:-${AI_EDITOR:-opencode}}"
    local wt_path
    wt_path=$(require_worktree_path "$branch")

    # Try to focus an existing tab first.
    if [[ -n "${ZELLIJ:-}" ]] && zellij action go-to-tab-name "$branch" 2>/dev/null; then
        return 0
    fi
    # Otherwise create the tab (works inside Zellij or against the grove session).
    AI_EDITOR="$ai_editor" maybe_add_zellij_tab "$wt_path" "$branch"
    if [[ -n "${ZELLIJ:-}" ]]; then
        zellij action go-to-tab-name "$branch" 2>/dev/null || true
    fi
}

# Live dashboard of running AI agents (refreshes every 5s).
cmd_agents() {
    local script="$SCRIPT_DIR/ai-status.sh"
    if [[ ! -f "$script" ]]; then
        echo "Error: ai-status.sh not found at $script" >&2
        exit 1
    fi
    while true; do
        clear
        bash "$script" || true
        sleep 5
    done
}

# Live worktree status dashboard (refreshes every 2s).
# Usage: cmd_status [repo-path]
cmd_status() {
    local script="$SCRIPT_DIR/worktree-status.sh"
    if [[ ! -f "$script" ]]; then
        echo "Error: worktree-status.sh not found at $script" >&2
        exit 1
    fi
    local target="${1:-$(pwd)}"
    while true; do
        clear
        bash "$script" "$target" || true
        sleep 2
    done
}

# Launch the full Grove workspace (delegates to launch-grove.sh).
# Usage: cmd_up [ai-editor] [path]
cmd_up() {
    exec "$SCRIPT_DIR/launch-grove.sh" up "$@"
}

# ─── Main Dispatch ────────────────────────────────────────────────────────────

usage() {
    cat <<'EOF'
Grove — git-style worktree & AI workspace CLI

Usage:
  grove <command> [args]        (also: git-worktree.sh <command> [args])

Workspace
  up [ai-editor] [path]         Launch Zellij, one tab per worktree
  status [path]                 Live worktree status dashboard
  agents                        Live dashboard of running AI agents

Worktrees
  new    <branch>               Create a new branch + worktree
  add    <branch>               Add a worktree for an existing branch
  ls                            List all worktrees
  rm     <branch>               Remove a worktree (prompts to delete branch)
  cd     <branch>               Jump into a worktree (shell cwd)
  main                          Jump into the main worktree (shell cwd)
  which  <branch>               Print a worktree's path
  root                          Print the main worktree path
  run    <branch> [--] <cmd>    Run a command inside a worktree's directory
  exec   [--] <cmd>             Run a command in EVERY worktree (fan-out)
  sync   [branch]               Fetch + rebase the branch onto its base
  pr     [branch]               Open (or create) the branch's GitHub PR
  mv     <branch> <new-path>    Move a worktree to a new directory
  log    [branch]               git log of the branch vs base
  open   <branch>               Open a worktree in your editor ($GROVE_EDITOR)
  info   [branch]               Show path, HEAD, ahead/behind, dirty status
  diff   [branch]               git diff --stat between branch and base
  rename <old> <new>            Rename a worktree's branch
  prune                         Remove worktrees for merged/stale branches
  lock   <path>                 Lock a worktree
  unlock <path>                 Unlock a worktree
  tab    [--layout-only]        Launch Zellij tabs (or print the layout)

AI & navigation
  go     <branch>               Jump to the worktree's Zellij tab (or attach)
  agent  <branch> [ai]          Open/focus an AI agent tab for a worktree
  agents                        Live dashboard of running AI agents

Other
  help                          Show this help message

Note: 'cd' and 'main' only change your shell's cwd via the grove() shell
function (sourced from git-worktree-aliases.sh). Run from there, not directly.

Environment Variables:
  GWT_BASE_BRANCH    Base branch for prune/diff/sync/log (default: origin/HEAD or main)
  GWT_WORKTREE_DIR   Override worktree parent directory
  GROVE_EDITOR       Editor for 'grove open' (default: $EDITOR or code)
  AI_EDITOR          Default AI editor for 'grove agent' (default: opencode)

Examples:
  grove new feat/checkout                  # branch + worktree
  grove run feat/checkout -- npm run dev   # dev server in that worktree
  grove exec -- git fetch                  # fan-out to all worktrees
  grove sync feat/checkout                 # rebase onto origin/main
  grove pr feat/checkout                   # open or create the PR
  grove agents                             # see running agents
  grove go feat/checkout                   # jump to that agent's tab
EOF
}

COMMAND="${1:-help}"
shift || true

case "$COMMAND" in
    up)     cmd_up "$@" ;;
    status) cmd_status "$@" ;;
    agents) cmd_agents ;;
    new)    cmd_new "$@" ;;
    add)    cmd_add "$@" ;;
    ls|list) cmd_ls ;;
    rm)     cmd_rm "$@" ;;
    which|cd) cmd_which "$@" ;;
    pick)   cmd_pick ;;
    root)   cmd_root ;;
    run)    cmd_run "$@" ;;
    exec)   cmd_exec "$@" ;;
    sync)   cmd_sync "$@" ;;
    pr)     cmd_pr "$@" ;;
    mv)     cmd_mv "$@" ;;
    log)    cmd_log "$@" ;;
    open)   cmd_open "$@" ;;
    go)     cmd_go "$@" ;;
    agent)  cmd_agent "$@" ;;
    prune)  cmd_prune ;;
    tab)    cmd_tab "$@" ;;
    info)   cmd_info "$@" ;;
    diff)   cmd_diff "$@" ;;
    rename) cmd_rename "$@" ;;
    lock)   cmd_lock "$@" ;;
    unlock) cmd_unlock "$@" ;;
    help|--help|-h) usage ;;
    *)
        echo "Unknown command: $COMMAND"
        echo "Run 'grove help' for usage."
        exit 1
        ;;
esac
