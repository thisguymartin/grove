#!/usr/bin/env bash
# Archived Grove wt* aliases; the wt name now belongs to worktrunk. Loaded only when GROVE_LEGACY_ALIASES=1.

_grove_toolkit() {
    bash "$GROVE_INSTALL_DIR/git-worktree.sh" "$@"
}

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
