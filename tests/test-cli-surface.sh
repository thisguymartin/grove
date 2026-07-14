#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d /tmp/grove-cli-surface-XXXXXXXX)"
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

assert_not_contains() {
    local haystack="$1"
    local needle="$2"
    local label="$3"
    [[ "$haystack" != *"$needle"* ]] || fail "$label: did not expect '$needle'"
}

REPO_DIR="$TMP_DIR/demo"
FAKE_BIN="$TMP_DIR/bin"
CONFIG_DIR="$TMP_DIR/config"
ZELLIJ_STATE="$TMP_DIR/zellij-state"
ZELLIJ_LOG="$TMP_DIR/zellij.log"
mkdir -p "$REPO_DIR" "$FAKE_BIN" "$CONFIG_DIR/grove"

git -C "$REPO_DIR" init -q
git -C "$REPO_DIR" config user.name "Grove Tests"
git -C "$REPO_DIR" config user.email "grove@example.com"
touch "$REPO_DIR/README.md"
git -C "$REPO_DIR" add README.md
git -C "$REPO_DIR" commit -qm "test fixture"
printf 'default_ai=codex\n' > "$CONFIG_DIR/grove/config"

cat > "$FAKE_BIN/codex" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$FAKE_BIN/codex"

cat > "$FAKE_BIN/zellij" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$ZELLIJ_LOG"
case "${1:-}" in
    list-sessions)
        if [[ -s "$ZELLIJ_STATE" ]]; then
            cat "$ZELLIJ_STATE"
        fi
        ;;
    kill-session|delete-session)
        : > "$ZELLIJ_STATE"
        ;;
esac
EOF
chmod +x "$FAKE_BIN/zellij"

cat > "$FAKE_BIN/gh" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
chmod +x "$FAKE_BIN/gh"

run_grove() {
    (
        cd "$REPO_DIR"
        PATH="$FAKE_BIN:$PATH" \
        XDG_CONFIG_HOME="$CONFIG_DIR" \
        ZELLIJ_STATE="$ZELLIJ_STATE" \
        ZELLIJ_LOG="$ZELLIJ_LOG" \
            bash "$ROOT_DIR/launch-grove.sh" "$@"
    )
}

: > "$ZELLIJ_STATE"
: > "$ZELLIJ_LOG"
run_grove >/dev/null
log="$(<"$ZELLIJ_LOG")"
assert_contains "$log" "--new-session-with-layout" "bare grove launches inside a repo"

printf 'grove-demo\n' > "$ZELLIJ_STATE"
: > "$ZELLIJ_LOG"
run_grove up --fresh >/dev/null
log="$(<"$ZELLIJ_LOG")"
assert_contains "$log" "kill-session grove-demo" "up --fresh forwards replacement flag"
assert_contains "$log" "--new-session-with-layout" "up --fresh recreates session"

short_help="$(bash "$ROOT_DIR/launch-grove.sh" help)"
assert_contains "$short_help" "grove new <branch>" "short help includes daily create"
assert_contains "$short_help" "grove status" "short help includes status"
assert_not_contains "$short_help" "grove exec" "short help hides advanced commands"

full_help="$(bash "$ROOT_DIR/launch-grove.sh" help --all)"
assert_contains "$full_help" "grove exec" "full help includes advanced commands"
assert_contains "$full_help" "wtab" "full help includes compatibility commands"

outside_help="$(cd "$TMP_DIR" && bash "$ROOT_DIR/launch-grove.sh")"
assert_contains "$outside_help" "grove help --all" "bare grove outside repo shows concise help"

printf 'cli surface tests passed\n'
