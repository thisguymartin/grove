#!/usr/bin/env fish
# Archived Grove wt* aliases; the wt name now belongs to worktrunk. Loaded only when GROVE_LEGACY_ALIASES=1.

function _grove_toolkit
    bash "$GROVE_INSTALL_DIR/git-worktree.sh" $argv
end

function wta; _grove_toolkit add $argv; end
function wtab; _grove_toolkit new $argv; end
function wtls; _grove_toolkit ls $argv; end
function wtinfo; _grove_toolkit info $argv; end
function wtdiff; _grove_toolkit diff $argv; end
function wtrn; _grove_toolkit rename $argv; end
function wtlock; _grove_toolkit lock $argv; end
function wtunlock; _grove_toolkit unlock $argv; end
function wtstatus; _grove_toolkit status $argv; end

function wtp
    if test (count $argv) -gt 0
        env GWT_BASE_BRANCH="$argv[1]" bash "$GROVE_INSTALL_DIR/git-worktree.sh" prune
    else
        _grove_toolkit prune
    end
end

# wtrm historically accepts a path and force-removes it. Preserve that contract.
function wtrm
    if test (count $argv) -eq 0
        echo "Usage: wtrm <worktree-path>"
        return 1
    end
    git worktree remove --force $argv
end

function wtcd
    if test (count $argv) -eq 0
        echo "Usage: wtcd <branch>"
        return 1
    end
    set -l wt_path (_grove_toolkit which $argv[1]); or return 1
    echo "Changing to worktree: $wt_path"
    cd "$wt_path"
end

function wtco; wtcd $argv; end

function wtui
    set -l repo_path (pwd)
    if test (count $argv) -gt 0
        set repo_path $argv[1]
    end
    bash "$GROVE_INSTALL_DIR/launch-worktrees.sh" "$repo_path"
end
