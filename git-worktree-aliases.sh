#!/usr/bin/env bash
# Grove shell integration for Bash and Zsh.
# Source this file from ~/.bashrc, ~/.bash_profile, or ~/.zshrc.

if [[ -n "${BASH_SOURCE[0]:-}" ]]; then
    GROVE_INSTALL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
elif [[ -n "${ZSH_VERSION:-}" ]]; then
    GROVE_INSTALL_DIR="$(cd "$(dirname "${(%):-%x}")" && pwd)"
else
    GROVE_INSTALL_DIR="$(cd "$(dirname "$0")" && pwd)"
fi

_grove_toolkit() {
    bash "$GROVE_INSTALL_DIR/git-worktree.sh" "$@"
}

# Legacy worktree commands remain thin compatibility wrappers.
wta() { _grove_toolkit add "$@"; }
wtab() { _grove_toolkit new "$@"; }
wtls() { _grove_toolkit ls "$@"; }
wtinfo() { _grove_toolkit info "$@"; }
wtdiff() { _grove_toolkit diff "$@"; }
wtrn() { _grove_toolkit rename "$@"; }
wtlock() { _grove_toolkit lock "$@"; }
wtunlock() { _grove_toolkit unlock "$@"; }
wtstatus() { _grove_toolkit status "$@"; }

wtp() {
    if [[ -n "${1:-}" ]]; then
        GWT_BASE_BRANCH="$1" _grove_toolkit prune
    else
        _grove_toolkit prune
    fi
}

# wtrm historically accepts a path and force-removes it. Preserve that contract.
wtrm() {
    if [[ -z "${1:-}" ]]; then
        echo "Usage: wtrm <worktree-path>"
        return 1
    fi
    git worktree remove --force "$@"
}

wtcd() {
    if [[ -z "${1:-}" ]]; then
        echo "Usage: wtcd <branch>"
        return 1
    fi
    local wt_path
    wt_path="$(_grove_toolkit which "$1")" || return 1
    echo "Changing to worktree: $wt_path"
    cd "$wt_path" || return 1
}

wtco() { wtcd "$@"; }

wtui() {
    bash "$GROVE_INSTALL_DIR/launch-worktrees.sh" "${1:-$(pwd)}"
}

grove() {
    local launcher="$GROVE_INSTALL_DIR/launch-grove.sh"
    local toolkit="$GROVE_INSTALL_DIR/git-worktree.sh"

    case "${1:-}" in
        cd)
            if [[ -z "${2:-}" ]]; then
                echo "Usage: grove cd <branch>"
                return 1
            fi
            local wt_path
            wt_path="$(bash "$toolkit" which "$2")" || return 1
            echo "Changing to worktree: $wt_path"
            cd "$wt_path" || return 1
            ;;
        main)
            local root_path
            root_path="$(bash "$toolkit" root)" || return 1
            echo "Changing to main worktree: $root_path"
            cd "$root_path" || return 1
            ;;
        pick)
            local picked
            picked="$(bash "$toolkit" pick)" || return 1
            [[ -n "$picked" ]] || return 1
            echo "Changing to worktree: $picked"
            cd "$picked" || return 1
            ;;
        *)
            bash "$launcher" "$@"
            ;;
    esac
}

zj-kill() {
    echo "Killing all Zellij sessions..."
    zellij kill-all-sessions 2>/dev/null || true
    zellij delete-all-sessions 2>/dev/null || true
    echo "Done."
}

_grove_complete() {
    local cur commands
    cur="${COMP_WORDS[COMP_CWORD]}"
    commands="$(bash "$GROVE_INSTALL_DIR/launch-grove.sh" __commands 2>/dev/null)"

    if [[ "$COMP_CWORD" -eq 1 ]]; then
        COMPREPLY=( $(compgen -W "$commands claude gemini opencode codex wt worktree --help -h" -- "$cur") )
        return
    fi

    COMPREPLY=( $(compgen -d -- "$cur") )
}

if [[ -n "${ZSH_VERSION:-}" ]]; then
    autoload -U +X bashcompinit 2>/dev/null && bashcompinit 2>/dev/null
fi
if [[ -n "${BASH_VERSION:-}" || -n "${ZSH_VERSION:-}" ]]; then
    complete -F _grove_complete grove 2>/dev/null
fi
