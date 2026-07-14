#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    exit 1
}

# shellcheck source=../lib/session.sh
source "$ROOT_DIR/lib/session.sh"

short_name="$(grove_session_name grove)"
[[ "$short_name" == "grove-grove" ]] || fail "short repo name changed: $short_name"

long_name="$(grove_session_name selective-agent-install)"
[[ ${#long_name} -le 24 ]] || fail "long session name exceeds Zellij's 24-character limit: $long_name"
[[ "$long_name" == grove-selective-* ]] || fail "long session name lost its readable prefix: $long_name"
[[ "$long_name" == "$(grove_session_name selective-agent-install)" ]] || fail "session name is not deterministic"
[[ "$long_name" != "$(grove_session_name selective-agent-inspector)" ]] || fail "different repo names collided"

printf 'session name tests passed\n'
