#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d /tmp/grove-agent-config-XXXXXXXX)"
trap 'rm -rf "$TMP_DIR"' EXIT

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    exit 1
}

assert_eq() {
    local actual="$1"
    local expected="$2"
    local label="$3"

    [[ "$actual" == "$expected" ]] || fail "$label: expected '$expected', got '$actual'"
}

export HOME="$TMP_DIR/home"
export XDG_CONFIG_HOME="$TMP_DIR/config"
mkdir -p "$HOME" "$XDG_CONFIG_HOME/grove"

# shellcheck source=../lib/ai-agent.sh
source "$ROOT_DIR/lib/ai-agent.sh"

unset AI_EDITOR
assert_eq "$(grove_resolve_ai "codex")" "codex" "explicit agent"

AI_EDITOR="claude"
assert_eq "$(grove_resolve_ai "")" "claude" "AI_EDITOR override"

unset AI_EDITOR
printf 'default_ai=gemini\n' > "$XDG_CONFIG_HOME/grove/config"
assert_eq "$(grove_resolve_ai "")" "gemini" "saved default"

rm "$XDG_CONFIG_HOME/grove/config"
assert_eq "$(grove_resolve_ai "")" "opencode" "legacy fallback"

printf 'default_ai=not-a-real-agent\n' > "$XDG_CONFIG_HOME/grove/config"
if grove_resolve_ai "" >"$TMP_DIR/stdout" 2>"$TMP_DIR/stderr"; then
    fail "invalid saved agent should fail"
fi
grep -q "Invalid default_ai" "$TMP_DIR/stderr" || fail "invalid config error"

printf 'default_ai=none\n' > "$XDG_CONFIG_HOME/grove/config"
if grove_require_ai "" >"$TMP_DIR/stdout" 2>"$TMP_DIR/stderr"; then
    fail "none should fail for agent-required commands"
fi
grep -q "No default AI agent is configured" "$TMP_DIR/stderr" || fail "none setup guidance"

printf 'default_ai=codex\n' > "$XDG_CONFIG_HOME/grove/config"
if PATH="/usr/bin:/bin" grove_require_ai "" >"$TMP_DIR/stdout" 2>"$TMP_DIR/stderr"; then
    fail "missing saved agent should fail"
fi
grep -q "AI agent 'codex' is not installed" "$TMP_DIR/stderr" || fail "missing agent guidance"

printf 'agent config tests passed\n'
