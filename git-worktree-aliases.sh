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

# Identify the installation directory of Grove
if [[ -n "${BASH_SOURCE[0]:-}" ]]; then
    GROVE_INSTALL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
elif [[ -n "${ZSH_VERSION:-}" ]]; then
    GROVE_INSTALL_DIR="$(cd "$(dirname "${(%):-%x}")" && pwd)"
else
    GROVE_INSTALL_DIR="$(cd "$(dirname "$0")" && pwd)"
fi

# ---------------------------------------------------------------------------
# wta — add worktree for an EXISTING upstream branch
# Usage: wta <existing-branch>
# ---------------------------------------------------------------------------
wta() {
    if [[ -z "${1:-}" ]]; then
        echo "Usage: wta <existing-branch>"
        return 1
    fi
    bash "$GROVE_INSTALL_DIR/git-worktree.sh" add "$1"
}

# ---------------------------------------------------------------------------
# wtab — add worktree AND create a new branch
# Usage: wtab <new-branch-name>
# ---------------------------------------------------------------------------
wtab() {
    if [[ -z "${1:-}" ]]; then
        echo "Usage: wtab <new-branch-name>"
        return 1
    fi
    bash "$GROVE_INSTALL_DIR/git-worktree.sh" new "$1"
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
# wtco — alias for wtcd
# ---------------------------------------------------------------------------
alias wtco='wtcd'

# ---------------------------------------------------------------------------
# wtcd — cd into a worktree by branch name
# Usage: wtcd <branch>
# ---------------------------------------------------------------------------
wtcd() {
    if [[ -z "${1:-}" ]]; then
        echo "Usage: wtcd <branch>"
        return 1
    fi
    local branch="$1"
    local wt_path
    wt_path=$(bash "$GROVE_INSTALL_DIR/git-worktree.sh" cd "$branch")
    if [[ $? -ne 0 ]]; then
        return 1
    fi
    echo "Changing to worktree: $wt_path"
    cd "$wt_path" || return 1
}

# ---------------------------------------------------------------------------
# wtinfo — show info about a worktree (path, HEAD, ahead/behind, dirty)
# Usage: wtinfo [branch]   (defaults to current branch)
# ---------------------------------------------------------------------------
wtinfo() {
    local branch="${1:-$(git symbolic-ref --short HEAD 2>/dev/null)}"
    if [[ -z "$branch" ]]; then
        echo "Error: not on a branch and no branch specified"
        return 1
    fi

    local wt_path head_sha
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
        return 1
    fi

    echo "Branch:  $branch"
    echo "Path:    $wt_path"
    echo "HEAD:    ${head_sha:0:10}"

    # Ahead/behind vs remote
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

    # Dirty status
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

# ---------------------------------------------------------------------------
# wtdiff — git diff --stat between a worktree branch and the base branch
# Usage: wtdiff [branch]   (defaults to current branch)
# ---------------------------------------------------------------------------
wtdiff() {
    local branch="${1:-$(git symbolic-ref --short HEAD 2>/dev/null)}"
    if [[ -z "$branch" ]]; then
        echo "Error: not on a branch and no branch specified"
        return 1
    fi

    local default_base
    default_base=$(git symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null \
        | sed 's@^origin/@@' || true)
    local base="${GWT_BASE_BRANCH:-${default_base:-main}}"

    echo "Diff: $branch vs $base"
    echo "─────────────────────────────────────────"
    git diff --stat "$base...$branch"
}

# ---------------------------------------------------------------------------
# wtrn — rename a worktree's branch
# Usage: wtrn <old-branch> <new-branch>
# ---------------------------------------------------------------------------
wtrn() {
    if [[ -z "${1:-}" || -z "${2:-}" ]]; then
        echo "Usage: wtrn <old-branch> <new-branch>"
        return 1
    fi
    local old="$1" new="$2"

    # Check that the old branch exists
    if ! git show-ref --verify --quiet "refs/heads/$old"; then
        echo "Error: branch '$old' does not exist"
        return 1
    fi

    git branch -m "$old" "$new"
    echo "Branch renamed: $old -> $new"

    # Warn about path mismatch
    local wt_path
    wt_path=$(git worktree list --porcelain | awk -v br="refs/heads/$new" '
        /^worktree / { wt = substr($0, 10) }
        /^branch /   { if (substr($0, 8) == br) print wt }
    ')
    if [[ -n "$wt_path" ]]; then
        echo "Note: worktree path is still: $wt_path"
        echo "  The directory was not renamed. You may want to recreate the worktree"
        echo "  if the path mismatch is confusing."
    fi
}

# ---------------------------------------------------------------------------
# wtlock / wtunlock — lock or unlock a worktree
# Usage: wtlock <path>   wtunlock <path>
# ---------------------------------------------------------------------------
wtlock() {
    if [[ -z "${1:-}" ]]; then
        echo "Usage: wtlock <path>"
        return 1
    fi
    git worktree lock "$1"
    echo "Worktree locked: $1"
}

wtunlock() {
    if [[ -z "${1:-}" ]]; then
        echo "Usage: wtunlock <path>"
        return 1
    fi
    git worktree unlock "$1"
    echo "Worktree unlocked: $1"
}

# ---------------------------------------------------------------------------
# wtstatus — show live worktree status dashboard (standalone, no Zellij)
# Usage: wtstatus [repo-path]
# ---------------------------------------------------------------------------
wtstatus() {
    local status_script="$GROVE_INSTALL_DIR/worktree-status.sh"
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
    local launcher="$GROVE_INSTALL_DIR/launch-worktrees.sh"
    if [[ ! -f "$launcher" ]]; then
        echo "Error: launch-worktrees.sh not found at $launcher"
        return 1
    fi

    bash "$launcher" "${1:-$(pwd)}"
}

# ---------------------------------------------------------------------------
# grove — launch the full AI-native workspace (God Mode)
# Usage: grove [path] [ai-editor]
#   grove                        # show help
#   grove .                      # current dir, opencode
#   grove claude                 # current dir, claude (explicit override)
#   grove gemini                 # current dir, gemini
#   grove codex                  # current dir, codex
#   grove /path/to/repo          # specific dir, opencode
#   grove /path/to/repo gemini   # specific dir, gemini
#
# Works from any git repo. Launches Zellij with one tab per worktree,
# each containing LazyGit + AI Agent + Workbench.
# Auto-kills any existing session with the same name before launching.
# ---------------------------------------------------------------------------
grove() {
    local launcher="$GROVE_INSTALL_DIR/launch-grove.sh"
    if [[ ! -f "$launcher" ]]; then
        echo "Error: launch-grove.sh not found at $launcher"
        return 1
    fi

    # Pass wt/worktree subcommands through with all remaining args
    if [[ "${1:-}" == "wt" || "${1:-}" == "worktree" ]]; then
        bash "$launcher" "$@"
        return
    fi

    bash "$launcher" "$@"
}

# ---------------------------------------------------------------------------
# zj-kill — kill all Zellij sessions (clean slate)
# Usage: zj-kill
# ---------------------------------------------------------------------------
zj-kill() {
    echo "Killing all Zellij sessions..."
    zellij kill-all-sessions 2>/dev/null || true
    zellij delete-all-sessions 2>/dev/null || true
    echo "Done."
}
