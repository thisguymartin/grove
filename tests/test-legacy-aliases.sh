#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    exit 1
}

defined_functions() {
    (
        if [[ -n "${1:-}" ]]; then
            export GROVE_LEGACY_ALIASES="$1"
        else
            unset GROVE_LEGACY_ALIASES
        fi
        source "$ROOT_DIR/git-worktree-aliases.sh"
        declare -F | awk '{ print $3 }'
    )
}

default_functions="$(defined_functions "")"
grep -qx grove <<< "$default_functions" || fail "grove should be defined by default"
grep -qx zj-kill <<< "$default_functions" || fail "zj-kill should be defined by default"
if grep -qx wtab <<< "$default_functions"; then
    fail "wtab should not be defined without GROVE_LEGACY_ALIASES=1"
fi

legacy_functions="$(defined_functions 1)"
for fn in grove wta wtab wtls wtinfo wtdiff wtrn wtlock wtunlock wtstatus wtp wtrm wtcd wtco wtui; do
    grep -qx "$fn" <<< "$legacy_functions" || fail "$fn should be defined with GROVE_LEGACY_ALIASES=1"
done

fish_source="$(<"$ROOT_DIR/git-worktree-aliases.fish")"
[[ "$fish_source" != *"function wtab"* ]] || fail "Fish aliases should not define wtab directly"
[[ "$fish_source" == *"legacy/wt-aliases.fish"* ]] || fail "Fish aliases should load the legacy file on opt-in"

printf 'legacy aliases tests passed\n'
