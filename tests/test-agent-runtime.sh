#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d /tmp/grove-agent-runtime-XXXXXXXX)"
trap 'rm -rf "$TMP_DIR"' EXIT

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    exit 1
}

assert_contains() {
    local haystack="$1"
    local needle="$2"
    local label="$3"
    [[ "$haystack" == *"$needle"* ]] || fail "$label: expected '$needle'"
}

export HOME="$TMP_DIR/home"
export XDG_CONFIG_HOME="$TMP_DIR/config"
mkdir -p "$HOME" "$XDG_CONFIG_HOME/grove" "$TMP_DIR/bin"

for agent in codex claude gemini opencode; do
    printf '#!/usr/bin/env bash\nexit 0\n' > "$TMP_DIR/bin/$agent"
    chmod +x "$TMP_DIR/bin/$agent"
done

printf 'default_ai=codex\n' > "$XDG_CONFIG_HOME/grove/config"
layout="$(PATH="$TMP_DIR/bin:/usr/bin:/bin" bash "$ROOT_DIR/launch-worktrees.sh" --layout-only "$ROOT_DIR")"
assert_contains "$layout" 'pane command="codex" name="AI Agent"' "saved default layout"

layout="$(PATH="$TMP_DIR/bin:/usr/bin:/bin" AI_EDITOR=claude bash "$ROOT_DIR/launch-worktrees.sh" --layout-only "$ROOT_DIR")"
assert_contains "$layout" 'pane command="claude" name="AI Agent"' "AI_EDITOR layout override"

layout="$(PATH="$TMP_DIR/bin:/usr/bin:/bin" AI_EDITOR=claude bash "$ROOT_DIR/launch-worktrees.sh" --layout-only --ai gemini "$ROOT_DIR")"
assert_contains "$layout" 'pane command="gemini" name="AI Agent"' "explicit layout override"

printf 'default_ai=none\n' > "$XDG_CONFIG_HOME/grove/config"
layout="$(PATH="$TMP_DIR/bin:/usr/bin:/bin" bash "$ROOT_DIR/launch-worktrees.sh" --layout-only --ai codex "$ROOT_DIR")"
assert_contains "$layout" 'pane command="codex" name="AI Agent"' "explicit agent over none"

if PATH="$TMP_DIR/bin:/usr/bin:/bin" bash "$ROOT_DIR/launch-worktrees.sh" --layout-only "$ROOT_DIR" \
    >"$TMP_DIR/stdout" 2>"$TMP_DIR/stderr"; then
    fail "saved none should stop agent layout generation"
fi
assert_contains "$(<"$TMP_DIR/stderr")" "No default AI agent is configured" "saved none guidance"

printf 'agent runtime tests passed\n'
