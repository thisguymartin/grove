#!/usr/bin/env fish
# Grove shell integration for Fish.
# Source this file from ~/.config/fish/config.fish.

set -g GROVE_INSTALL_DIR (realpath (dirname (status --current-filename)))

function _grove_toolkit
    bash "$GROVE_INSTALL_DIR/git-worktree.sh" $argv
end

# Legacy worktree commands remain thin compatibility wrappers.
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

function grove
    set -l launcher "$GROVE_INSTALL_DIR/launch-grove.sh"
    set -l toolkit "$GROVE_INSTALL_DIR/git-worktree.sh"
    set -l command ""
    if test (count $argv) -gt 0
        set command $argv[1]
    end

    switch $command
        case cd
            if test (count $argv) -lt 2
                echo "Usage: grove cd <branch>"
                return 1
            end
            set -l wt_path (bash "$toolkit" which $argv[2]); or return 1
            echo "Changing to worktree: $wt_path"
            cd "$wt_path"
        case main
            set -l root_path (bash "$toolkit" root); or return 1
            echo "Changing to main worktree: $root_path"
            cd "$root_path"
        case pick
            set -l picked (bash "$toolkit" pick); or return 1
            test -n "$picked"; or return 1
            echo "Changing to worktree: $picked"
            cd "$picked"
        case '*'
            bash "$launcher" $argv
    end
end

function zj-kill
    echo "Killing all Zellij sessions..."
    zellij kill-all-sessions 2>/dev/null; or true
    zellij delete-all-sessions 2>/dev/null; or true
    echo "Done."
end

complete -c grove -f
complete -c grove -n "__fish_use_subcommand" \
    -a "(bash $GROVE_INSTALL_DIR/launch-grove.sh __commands) claude gemini opencode codex wt worktree"
