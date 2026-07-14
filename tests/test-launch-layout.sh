#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    exit 1
}

assert_contains() {
    local haystack="$1"
    local needle="$2"
    local label="$3"

    if [[ "$haystack" != *"$needle"* ]]; then
        fail "$label: expected to find '$needle'"
    fi
}

assert_not_contains() {
    local haystack="$1"
    local needle="$2"
    local label="$3"

    if [[ "$haystack" == *"$needle"* ]]; then
        fail "$label: did not expect to find '$needle'"
    fi
}

ZJSTATUS_WASM="$ROOT_DIR/vendor/zjstatus/zjstatus.wasm"
MOVED_WASM=""

restore_wasm() {
    if [[ -n "$MOVED_WASM" && -f "$MOVED_WASM" ]]; then
        mv "$MOVED_WASM" "$ZJSTATUS_WASM"
    fi
}

trap restore_wasm EXIT

[[ -f "$ZJSTATUS_WASM" ]] || fail "vendored zjstatus.wasm is missing"

default_layout="$(bash ./launch-worktrees.sh --layout-only .)"
assert_contains "$default_layout" "plugin location=\"file:$ZJSTATUS_WASM\"" "default custom layout"
assert_contains "$default_layout" 'format_center "{tabs}"' "default custom layout"
assert_contains "$default_layout" 'format_left' "default custom layout"
assert_contains "$default_layout" 'name="Overview Status"' "single overview renderer"
assert_contains "$default_layout" 'GROVE_STATUS_BIN' "experimental status binary hook"
assert_contains "$default_layout" 'sleep 30' "overview refresh interval"
assert_not_contains "$default_layout" 'name="AI Status"' "no default AI monitor"
assert_not_contains "$default_layout" 'name="PR Status"' "no default PR monitor"
assert_not_contains "$default_layout" 'name="CI / GitHub Actions"' "no default CI monitor"
assert_not_contains "$default_layout" 'name="Global Stash & WIP"' "no default stash monitor"
assert_not_contains "$default_layout" 'name="Resources"' "no default resource monitor"
assert_not_contains "$default_layout" 'plugin location="zellij:tab-bar"' "default custom layout"
assert_not_contains "$default_layout" 'plugin location="zellij:status-bar"' "default custom layout"
assert_not_contains "$default_layout" '🟢' "default custom layout"
assert_not_contains "$default_layout" '🤖' "default custom layout"

stock_layout="$(GROVE_ZELLIJ_BAR=stock bash ./launch-worktrees.sh --layout-only .)"
assert_contains "$stock_layout" 'plugin location="zellij:tab-bar"' "stock fallback layout"
assert_contains "$stock_layout" 'plugin location="zellij:status-bar"' "stock fallback layout"
assert_not_contains "$stock_layout" "plugin location=\"file:$ZJSTATUS_WASM\"" "stock fallback layout"

MOVED_WASM="$(mktemp /tmp/grove-zjstatus-wasm-XXXXXXXX)"
missing_stderr="$(mktemp /tmp/grove-zjstatus-stderr-XXXXXXXX)"
mv "$ZJSTATUS_WASM" "$MOVED_WASM"
missing_layout="$(bash ./launch-worktrees.sh --layout-only . 2>"$missing_stderr")"
mv "$MOVED_WASM" "$ZJSTATUS_WASM"
MOVED_WASM=""
missing_stderr_text="$(<"$missing_stderr")"
rm -f "$missing_stderr"

assert_contains "$missing_layout" 'plugin location="zellij:tab-bar"' "missing zjstatus fallback layout"
assert_contains "$missing_layout" 'plugin location="zellij:status-bar"' "missing zjstatus fallback layout"
assert_contains "$missing_stderr_text" "falling back to stock Zellij bars" "missing zjstatus fallback warning"

printf 'layout tests passed\n'
