#!/usr/bin/env fish
# Git Worktree Shell Aliases & Functions (fish shell)
#
# Source this file in your ~/.config/fish/config.fish:
#   source ~/.local/share/grove/git-worktree-aliases.fish
#
# Or add to your config with a one-liner:
#   echo 'source ~/.local/share/grove/git-worktree-aliases.fish' >> ~/.config/fish/config.fish
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
set -g GROVE_INSTALL_DIR (realpath (dirname (status --current-filename)))

# ---------------------------------------------------------------------------
# wta — add worktree for an EXISTING upstream branch
# Usage: wta <existing-branch>
# ---------------------------------------------------------------------------
function wta
    if test (count $argv) -eq 0
        echo "Usage: wta <existing-branch>"
        return 1
    end
    bash "$GROVE_INSTALL_DIR/git-worktree.sh" add $argv[1]
end

# ---------------------------------------------------------------------------
# wtab — add worktree AND create a new branch
# Usage: wtab <new-branch-name>
# ---------------------------------------------------------------------------
function wtab
    if test (count $argv) -eq 0
        echo "Usage: wtab <new-branch-name>"
        return 1
    end
    bash "$GROVE_INSTALL_DIR/git-worktree.sh" new $argv[1]
end

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
function wtp
    set -l default_branch (git symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null | sed 's@^origin/@@')
    set -l main_branch
    if test (count $argv) -gt 0
        set main_branch $argv[1]
    else if test -n "$default_branch"
        set main_branch $default_branch
    else
        set main_branch main
    end

    echo "Pruning worktrees merged into '$main_branch'..."
    git fetch -p origin >/dev/null 2>&1; or true
    git worktree prune

    set -l repo_root (git rev-parse --show-toplevel)

    git worktree list --porcelain | awk '
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
    ' | while read -l line
        set -l parts (string split \t -- $line)
        set -l wt $parts[1]
        set -l br (test (count $parts) -gt 1; and echo $parts[2]; or echo "")
        set -l locked (test (count $parts) -gt 2; and echo $parts[3]; or echo "")

        test -n "$wt"; or continue
        if test -n "$locked"
            echo "  Skipping (locked): $wt"
            continue
        end
        test "$wt" = "$repo_root"; and continue
        if test -z "$br"
            echo "  Skipping (detached HEAD): $wt"
            continue
        end

        set -l branch_name (string replace 'refs/heads/' '' -- $br)

        set -l wt_status (git -C "$wt" status --porcelain 2>/dev/null)
        if test -n "$wt_status"
            echo "  Skipping (dirty): $branch_name"
            continue
        end

        # Merged directly into main
        if git merge-base --is-ancestor "$branch_name" "$main_branch" 2>/dev/null
            echo "  Removing (merged): $branch_name"
            git worktree remove --force "$wt"
            continue
        end

        set -l base (git merge-base "$main_branch" "$branch_name" 2>/dev/null)
        test -n "$base"; or continue

        # Branch has no unique commits vs main
        if git diff --quiet "$base..$branch_name" 2>/dev/null
            echo "  Removing (no unique commits): $branch_name"
            git worktree remove --force "$wt"
            continue
        end

        # Squash-merge / rebase detection via patch-id
        set -l branch_patch (git diff "$base..$branch_name" | git patch-id --stable | awk '{print $1}' | head -n1 2>/dev/null)
        test -n "$branch_patch"; or continue

        set -l found ""
        for c in (git rev-list "$base..$main_branch" 2>/dev/null)
            set -l cid (git show --pretty=format: --no-color "$c" | git patch-id --stable | awk '{print $1}' | head -n1 2>/dev/null)
            if test "$cid" = "$branch_patch"
                set found $c
                break
            end
        end

        if test -n "$found"
            echo "  Removing (squash/rebase merged): $branch_name"
            git worktree remove --force "$wt"
        end
    end

    echo "Done."
end

# ---------------------------------------------------------------------------
# wtls — list all worktrees for this repo
# ---------------------------------------------------------------------------
function wtls
    git worktree list
end

# ---------------------------------------------------------------------------
# wtrm — force remove a worktree
# Usage: wtrm <worktree-path>
# ---------------------------------------------------------------------------
function wtrm
    git worktree remove --force $argv
end

# ---------------------------------------------------------------------------
# wtco — cd into a worktree by branch name
# Usage: wtco <branch>
# ---------------------------------------------------------------------------
function wtco
    wtcd $argv
end

# ---------------------------------------------------------------------------
# wtcd — cd into a worktree by branch name
# Usage: wtcd <branch>
# ---------------------------------------------------------------------------
function wtcd
    if test (count $argv) -eq 0
        echo "Usage: wtcd <branch>"
        return 1
    end
    set -l branch $argv[1]
    set -l wt_path (git worktree list --porcelain | awk -v br="refs/heads/$branch" '
        /^worktree / { wt = substr($0, 10) }
        /^branch /   { if (substr($0, 8) == br) print wt }
    ')
    if test -z "$wt_path"
        echo "No worktree found for branch '$branch'"
        return 1
    end
    echo "Changing to worktree: $wt_path"
    cd $wt_path
end

# ---------------------------------------------------------------------------
# wtinfo — show info about a worktree (path, HEAD, ahead/behind, dirty)
# Usage: wtinfo [branch]   (defaults to current branch)
# ---------------------------------------------------------------------------
function wtinfo
    set -l branch
    if test (count $argv) -gt 0
        set branch $argv[1]
    else
        set branch (git symbolic-ref --short HEAD 2>/dev/null)
    end
    if test -z "$branch"
        echo "Error: not on a branch and no branch specified"
        return 1
    end

    set -l wt_path ""
    set -l head_sha ""
    set -l found_branch 0

    while read -l line
        switch $line
            case 'worktree *'
                set wt_path (string replace 'worktree ' '' -- $line)
                set head_sha ""
                set found_branch 0
            case 'HEAD *'
                set head_sha (string replace 'HEAD ' '' -- $line)
            case "branch refs/heads/$branch"
                set found_branch 1
            case ''
                if test $found_branch -eq 0
                    set wt_path ""
                    set head_sha ""
                end
        end
    end < (git worktree list --porcelain | psub)

    if test -z "$wt_path"
        echo "No worktree found for branch '$branch'"
        return 1
    end

    echo "Branch:  $branch"
    echo "Path:    $wt_path"
    echo "HEAD:    "(string sub -l 10 -- $head_sha)

    # Ahead/behind vs remote
    set -l upstream (git -C "$wt_path" rev-parse --abbrev-ref "@{upstream}" 2>/dev/null)
    if test -n "$upstream"
        set -l ab (git -C "$wt_path" rev-list --left-right --count "$branch...$upstream" 2>/dev/null)
        if test -n "$ab"
            set -l ahead (echo $ab | awk '{print $1}')
            set -l behind (echo $ab | awk '{print $2}')
            echo "Remote:  $upstream (ahead $ahead, behind $behind)"
        end
    else
        echo "Remote:  (no upstream)"
    end

    # Dirty status
    set -l git_status (git -C "$wt_path" status --porcelain 2>/dev/null)
    if test -n "$git_status"
        set -l count (echo $git_status | wc -l | string trim)
        echo "Status:  dirty ($count changed file(s))"
    else
        echo "Status:  clean"
    end
end

# ---------------------------------------------------------------------------
# wtdiff — git diff --stat between a worktree branch and the base branch
# Usage: wtdiff [branch]   (defaults to current branch)
# ---------------------------------------------------------------------------
function wtdiff
    set -l branch
    if test (count $argv) -gt 0
        set branch $argv[1]
    else
        set branch (git symbolic-ref --short HEAD 2>/dev/null)
    end
    if test -z "$branch"
        echo "Error: not on a branch and no branch specified"
        return 1
    end

    set -l default_base (git symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null | sed 's@^origin/@@')
    set -l base
    if set -q GWT_BASE_BRANCH
        set base $GWT_BASE_BRANCH
    else if test -n "$default_base"
        set base $default_base
    else
        set base main
    end

    echo "Diff: $branch vs $base"
    echo "─────────────────────────────────────────"
    git diff --stat "$base...$branch"
end

# ---------------------------------------------------------------------------
# wtrn — rename a worktree's branch
# Usage: wtrn <old-branch> <new-branch>
# ---------------------------------------------------------------------------
function wtrn
    if test (count $argv) -lt 2
        echo "Usage: wtrn <old-branch> <new-branch>"
        return 1
    end
    set -l old $argv[1]
    set -l new $argv[2]

    if not git show-ref --verify --quiet "refs/heads/$old"
        echo "Error: branch '$old' does not exist"
        return 1
    end

    git branch -m "$old" "$new"
    echo "Branch renamed: $old -> $new"

    set -l wt_path (git worktree list --porcelain | awk -v br="refs/heads/$new" '
        /^worktree / { wt = substr($0, 10) }
        /^branch /   { if (substr($0, 8) == br) print wt }
    ')
    if test -n "$wt_path"
        echo "Note: worktree path is still: $wt_path"
        echo "  The directory was not renamed. You may want to recreate the worktree"
        echo "  if the path mismatch is confusing."
    end
end

# ---------------------------------------------------------------------------
# wtlock / wtunlock — lock or unlock a worktree
# Usage: wtlock <path>   wtunlock <path>
# ---------------------------------------------------------------------------
function wtlock
    if test (count $argv) -eq 0
        echo "Usage: wtlock <path>"
        return 1
    end
    git worktree lock $argv[1]
    echo "Worktree locked: $argv[1]"
end

function wtunlock
    if test (count $argv) -eq 0
        echo "Usage: wtunlock <path>"
        return 1
    end
    git worktree unlock $argv[1]
    echo "Worktree unlocked: $argv[1]"
end

# ---------------------------------------------------------------------------
# wtstatus — show live worktree status dashboard (standalone, no Zellij)
# Usage: wtstatus [repo-path]
# ---------------------------------------------------------------------------
function wtstatus
    set -l status_script "$GROVE_INSTALL_DIR/worktree-status.sh"
    if not test -f "$status_script"
        echo "Error: worktree-status.sh not found at $status_script"
        return 1
    end

    set -l repo_path
    if test (count $argv) -gt 0
        set repo_path $argv[1]
    else
        set repo_path (pwd)
    end
    watch -n 2 -c "$status_script" $repo_path
end

# ---------------------------------------------------------------------------
# wtui — launch a Zellij session with one tab per worktree (requires zellij)
# Usage: wtui [repo-path]
# ---------------------------------------------------------------------------
function wtui
    set -l launcher "$GROVE_INSTALL_DIR/launch-worktrees.sh"
    if not test -f "$launcher"
        echo "Error: launch-worktrees.sh not found at $launcher"
        return 1
    end

    set -l repo_path
    if test (count $argv) -gt 0
        set repo_path $argv[1]
    else
        set repo_path (pwd)
    end
    bash "$launcher" $repo_path
end

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
function grove
    set -l launcher "$GROVE_INSTALL_DIR/launch-grove.sh"
    if not test -f "$launcher"
        echo "Error: launch-grove.sh not found at $launcher"
        return 1
    end

    # Pass wt/worktree subcommands through with all remaining args
    if test (count $argv) -gt 0; and string match -q -r '^(wt|worktree)$' -- $argv[1]
        bash "$launcher" $argv
        return
    end

    set -l repo_path ""
    set -l ai_editor ""
    set -l remaining $argv

    # If first arg is a directory, treat as repo path
    if test (count $remaining) -gt 0; and test -d $remaining[1]
        set repo_path $remaining[1]
        set remaining $remaining[2..-1]
    end

    # Remaining arg (if any) is the AI editor
    if test (count $remaining) -gt 0
        set ai_editor $remaining[1]
    end

    if test -n "$repo_path"; and test -n "$ai_editor"
        bash "$launcher" "$repo_path" "$ai_editor"
    else if test -n "$repo_path"
        bash "$launcher" "$repo_path"
    else if test -n "$ai_editor"
        bash "$launcher" "$ai_editor"
    else
        bash "$launcher"
    end
end

# ---------------------------------------------------------------------------
# zj-kill — kill all Zellij sessions (clean slate)
# Usage: zj-kill
# ---------------------------------------------------------------------------
function zj-kill
    echo "Killing all Zellij sessions..."
    zellij kill-all-sessions 2>/dev/null; or true
    zellij delete-all-sessions 2>/dev/null; or true
    echo "Done."
end
