#!/usr/bin/env fish
# Grove shell integration for Fish.
# Source this file from ~/.config/fish/config.fish.

set -g GROVE_INSTALL_DIR (realpath (dirname (status --current-filename)))

if test "$GROVE_LEGACY_ALIASES" = 1
    source "$GROVE_INSTALL_DIR/legacy/wt-aliases.fish"
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
    -a "(bash $GROVE_INSTALL_DIR/launch-grove.sh __commands) claude gemini opencode codex"
