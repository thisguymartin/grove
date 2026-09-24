#!/usr/bin/env bash
# Worktree backend: worktrunk (`wt`) when installed, else plain git.
# GROVE_WORKTREE_BACKEND=git|worktrunk forces one.

grove_worktree_backend() {
    case "${GROVE_WORKTREE_BACKEND:-}" in
        git|worktrunk) printf '%s\n' "$GROVE_WORKTREE_BACKEND" ;;
        "")
            if command -v wt >/dev/null 2>&1; then
                printf 'worktrunk\n'
            else
                printf 'git\n'
            fi
            ;;
        *)
            echo "Error: GROVE_WORKTREE_BACKEND must be git or worktrunk" >&2
            return 1
            ;;
    esac
}
