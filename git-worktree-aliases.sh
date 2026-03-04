#!/usr/bin/env bash
# Git Worktree Shell Aliases & Functions
#
# Source this file in your ~/.zshrc or ~/.bashrc:
#   source ~/.local/share/grove/git-worktree-aliases.sh
#
# Or add to your shell config with a one-liner:
#   echo 'source ~/.local/share/grove/git-worktree-aliases.sh' >> ~/.zshrc
#
# Git config aliases (wta, wtab, wtp) are shell functions here for broader
# compatibility and richer output. wtls/wtrm are thin wrappers around git builtins.
#
# Worktrees are stored under a sibling "worktrees/<repo>/<branch>" directory,
# keeping them out of the repo root and easy to find.
#
# Example layout on disk:
#   ~/projects/
#   ├── my-repo/              <- main worktree (your repo)
#   └── worktrees/
#       └── my-repo/
#           ├── feature-auth/ <- wtab feature-auth
#           └── fix-login/    <- wtab fix-login

# ---------------------------------------------------------------------------
# wta — add worktree for an EXISTING upstream branch
# Usage: wta <existing-branch>
# ---------------------------------------------------------------------------
wta() {
    if [[ -z "$1" ]]; then
        echo "Usage: wta <existing-branch>"
        return 1
    fi
    local branch="$1"
    local cur_git_dir proj_dir repo_name target
    cur_git_dir=$(git rev-parse --show-toplevel 2>/dev/null) || {
        echo "Error: not inside a git repository"
        return 1
    }
    proj_dir=$(dirname "$cur_git_dir")
    repo_name=$(basename "$cur_git_dir")
    target="$proj_dir/worktrees/$repo_name/$branch"

    if [ -d "$target" ]; then
        echo "Worktree already exists at: $target"
    else
        echo "Adding worktree for branch '$branch' at: $target"
        git worktree add "$target" "$branch"
        echo "Done. cd into it with: cd $target"
    fi
}

# ---------------------------------------------------------------------------
# wtab — add worktree AND create a new branch
# Usage: wtab <new-branch-name>
# ---------------------------------------------------------------------------
wtab() {
    if [[ -z "$1" ]]; then
        echo "Usage: wtab <new-branch-name>"
        return 1
    fi
    local branch="$1"
    local cur_git_dir proj_dir repo_name target
    cur_git_dir=$(git rev-parse --show-toplevel 2>/dev/null) || {
        echo "Error: not inside a git repository"
        return 1
    }
    proj_dir=$(dirname "$cur_git_dir")
    repo_name=$(basename "$cur_git_dir")
    target="$proj_dir/worktrees/$repo_name/$branch"

    if [ -d "$target" ]; then
        echo "Worktree already exists at: $target"
    else
        echo "Creating new branch '$branch' with worktree at: $target"
        git worktree add "$target" -b "$branch"
        echo "Done. cd into it with: cd $target"
    fi
}

# ---------------------------------------------------------------------------
# wtp — prune worktrees that have been merged, rebased, or squash-merged to main
# Usage: wtp [main-branch]   (default: auto-detected or 'main')
#
# Skips worktrees that are:
#   - locked
#   - the main repo root
#   - detached HEAD
#   - have uncommitted changes
# ---------------------------------------------------------------------------
wtp() {
    local default_branch main_branch
    default_branch=$(git symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null \
        | sed 's@^origin/@@' || true)
    main_branch="${1:-${default_branch:-main}}"

    echo "Pruning worktrees merged into '$main_branch'..."
    git fetch -p origin >/dev/null 2>&1 || true
    git worktree prune

    local repo_root
    repo_root=$(git rev-parse --show-toplevel)

    while IFS=$'\t' read -r wt br locked; do
        [[ -n "$wt" ]] || continue
        [[ -n "$locked" ]] && { echo "  Skipping (locked): $wt"; continue; }
        [[ "$wt" == "$repo_root" ]] && continue
        [[ -z "$br" ]] && { echo "  Skipping (detached HEAD): $wt"; continue; }

        local branch_name="${br#refs/heads/}"

        if [[ -n "$(git -C "$wt" status --porcelain 2>/dev/null)" ]]; then
            echo "  Skipping (dirty): $branch_name"
            continue
        fi

        # Merged directly into main
        if git merge-base --is-ancestor "$branch_name" "$main_branch" 2>/dev/null; then
            echo "  Removing (merged): $branch_name"
            git worktree remove --force "$wt"
            continue
        fi

        local base
        base=$(git merge-base "$main_branch" "$branch_name" 2>/dev/null || true)
        [[ -z "$base" ]] && continue

        # Branch has no unique commits vs main
        if git diff --quiet "$base..$branch_name" 2>/dev/null; then
            echo "  Removing (no unique commits): $branch_name"
            git worktree remove --force "$wt"
            continue
        fi

        # Squash-merge / rebase detection via patch-id
        local branch_patch
        branch_patch=$(git diff "$base..$branch_name" | git patch-id --stable \
            | awk '{print $1}' | head -n1 2>/dev/null || true)
        [[ -z "$branch_patch" ]] && continue

        local found=""
        while IFS= read -r c; do
            local cid
            cid=$(git show --pretty=format: --no-color "$c" \
                | git patch-id --stable | awk '{print $1}' | head -n1 2>/dev/null || true)
            if [[ "$cid" == "$branch_patch" ]]; then
                found="$c"
                break
            fi
        done < <(git rev-list "$base..$main_branch" 2>/dev/null)

        if [[ -n "$found" ]]; then
            echo "  Removing (squash/rebase merged): $branch_name"
            git worktree remove --force "$wt"
        fi

    done < <(git worktree list --porcelain | awk '
        /^worktree / { wt = substr($0, 10) }
        /^branch /   { br = substr($0, 8) }
        /^detached/  { br = "" }
        /^locked/    { locked = "locked" }
        /^$/         {
            if (wt != "") {
                print wt "\t" br "\t" locked
                wt = br = locked = ""
            }
        }
        END { if (wt != "") print wt "\t" br "\t" locked }
    ')

    echo "Done."
}

# ---------------------------------------------------------------------------
# wtls — list all worktrees for this repo
# ---------------------------------------------------------------------------
alias wtls='git worktree list'

# ---------------------------------------------------------------------------
# wtrm — force remove a worktree
# Usage: wtrm <worktree-path>
# ---------------------------------------------------------------------------
alias wtrm='git worktree remove --force'

# ---------------------------------------------------------------------------
# wtstatus — show live worktree status dashboard (standalone, no Zellij)
# Usage: wtstatus [repo-path]
# ---------------------------------------------------------------------------
wtstatus() {
    local script_dir
    if [[ -n "${BASH_SOURCE[0]:-}" ]]; then
        script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    else
        # zsh
        script_dir="$(cd "$(dirname "$0")" && pwd)"
    fi

    local status_script="$script_dir/worktree-status.sh"
    if [[ ! -f "$status_script" ]]; then
        echo "Error: worktree-status.sh not found at $status_script"
        return 1
    fi

    watch -n 2 -c "$status_script" "${1:-$(pwd)}"
}

# ---------------------------------------------------------------------------
# wtui — launch a Zellij session with one tab per worktree (requires zellij)
# Usage: wtui [repo-path]
# ---------------------------------------------------------------------------
wtui() {
    local script_dir
    # Resolve the location of this script to find launch-worktrees.sh
    if [[ -n "${BASH_SOURCE[0]:-}" ]]; then
        script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    else
        # zsh
        script_dir="$(cd "$(dirname "$0")" && pwd)"
    fi

    local launcher="$script_dir/launch-worktrees.sh"
    if [[ ! -f "$launcher" ]]; then
        echo "Error: launch-worktrees.sh not found at $launcher"
        return 1
    fi

    bash "$launcher" "${1:-$(pwd)}"
}

# ---------------------------------------------------------------------------
# grove — launch the full AI-native workspace (God Mode)
# Usage: grove [ai-editor]   (default: claude, options: claude, gemini, opencode)
#
# Works from any git repo. Launches Zellij with one tab per worktree,
# each containing LazyGit + AI Agent + Workbench.
# Auto-kills any existing session with the same name before launching.
# ---------------------------------------------------------------------------
grove() {
    local script_dir
    if [[ -n "${BASH_SOURCE[0]:-}" ]]; then
        script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    else
        script_dir="$(cd "$(dirname "$0")" && pwd)"
    fi

    local launcher="$script_dir/launch-grove.sh"
    if [[ ! -f "$launcher" ]]; then
        echo "Error: launch-grove.sh not found at $launcher"
        return 1
    fi

    if [[ -n "${1:-}" ]]; then
        bash "$launcher" "$1"
    else
        bash "$launcher"
    fi
}

# ---------------------------------------------------------------------------
# zj-kill — kill all Zellij sessions (clean slate)
# Usage: zj-kill
# ---------------------------------------------------------------------------
zj-kill() {
    echo "Killing all Zellij sessions..."
    zellij kill-all-sessions 2>/dev/null || echo "No active sessions."
}
