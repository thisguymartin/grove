#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d /tmp/grove-session-lifecycle-XXXXXXXX)"
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
ZELLIJ_STATE="$TMP_DIR/zellij-state"
ZELLIJ_LOG="$TMP_DIR/zellij.log"
mkdir -p "$REPO_DIR" "$FAKE_BIN"

git -C "$REPO_DIR" init -q
git -C "$REPO_DIR" config user.name "Grove Tests"
git -C "$REPO_DIR" config user.email "grove@example.com"
touch "$REPO_DIR/README.md"
git -C "$REPO_DIR" add README.md
git -C "$REPO_DIR" commit -qm "test fixture"

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

run_launch() {
    PATH="$FAKE_BIN:$PATH" \
    ZELLIJ_STATE="$ZELLIJ_STATE" \
    ZELLIJ_LOG="$ZELLIJ_LOG" \
        bash "$ROOT_DIR/launch-worktrees.sh" --ai codex "$@" >/dev/null
}

printf 'grove-demo\n' > "$ZELLIJ_STATE"
: > "$ZELLIJ_LOG"
run_launch "$REPO_DIR"
log="$(<"$ZELLIJ_LOG")"
assert_contains "$log" "attach grove-demo" "existing session attaches"
assert_not_contains "$log" "kill-session grove-demo" "existing session survives"
assert_not_contains "$log" "--new-session-with-layout" "existing session is not recreated"

printf 'grove-demo\n' > "$ZELLIJ_STATE"
: > "$ZELLIJ_LOG"
run_launch --fresh "$REPO_DIR"
log="$(<"$ZELLIJ_LOG")"
assert_contains "$log" "kill-session grove-demo" "fresh launch kills existing session"
assert_contains "$log" "--new-session-with-layout" "fresh launch creates replacement"

printf 'grove-demo\n' > "$ZELLIJ_STATE"
: > "$ZELLIJ_LOG"
inside_output="$(
    PATH="$FAKE_BIN:$PATH" \
    ZELLIJ_STATE="$ZELLIJ_STATE" \
    ZELLIJ_LOG="$ZELLIJ_LOG" \
    ZELLIJ_SESSION_NAME="grove-demo" \
        bash "$ROOT_DIR/launch-worktrees.sh" --ai codex "$REPO_DIR"
)"
assert_contains "$inside_output" "already active" "inside target session is a no-op"
[[ ! -s "$ZELLIJ_LOG" ]] || fail "inside target session should not invoke Zellij"

printf 'session lifecycle tests passed\n'
