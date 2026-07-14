#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d /tmp/grove-go-navigation-XXXXXXXX)"
trap 'rm -rf "$TMP_DIR" /tmp/grove-layout-demo.kdl' EXIT

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

REPO_DIR="$TMP_DIR/demo"
WORKTREE_DIR="$TMP_DIR/feat-nav"
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
git -C "$REPO_DIR" worktree add -qb feat/nav "$WORKTREE_DIR"
printf 'default_ai=codex\n' > "$CONFIG_DIR/grove/config"

for command in codex lazygit; do
    cat > "$FAKE_BIN/$command" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
    chmod +x "$FAKE_BIN/$command"
done

cat > "$FAKE_BIN/gh" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
chmod +x "$FAKE_BIN/gh"

cat > "$FAKE_BIN/zellij" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$ZELLIJ_LOG"
if [[ "${1:-}" == "list-sessions" && -s "$ZELLIJ_STATE" ]]; then
    cat "$ZELLIJ_STATE"
fi
EOF
chmod +x "$FAKE_BIN/zellij"

run_go() {
    (
        cd "$REPO_DIR"
        PATH="$FAKE_BIN:$PATH" \
        XDG_CONFIG_HOME="$CONFIG_DIR" \
        ZELLIJ_STATE="$ZELLIJ_STATE" \
        ZELLIJ_LOG="$ZELLIJ_LOG" \
            bash "$ROOT_DIR/git-worktree.sh" go "$@"
    )
}

run_go_from_feature() {
    (
        cd "$WORKTREE_DIR"
        PATH="$FAKE_BIN:$PATH" \
        XDG_CONFIG_HOME="$CONFIG_DIR" \
        ZELLIJ_STATE="$ZELLIJ_STATE" \
        ZELLIJ_LOG="$ZELLIJ_LOG" \
            bash "$ROOT_DIR/git-worktree.sh" go "$@"
    )
}

printf 'grove-demo\n' > "$ZELLIJ_STATE"
: > "$ZELLIJ_LOG"
run_go feat/nav >/dev/null
log="$(<"$ZELLIJ_LOG")"
assert_contains "$log" "--session grove-demo action go-to-tab-name feat/nav" "background tab focus"
assert_contains "$log" "attach grove-demo" "attach follows background focus"

: > "$ZELLIJ_LOG"
run_go_from_feature feat/nav >/dev/null
log="$(<"$ZELLIJ_LOG")"
assert_contains "$log" "--session grove-demo action go-to-tab-name feat/nav" "linked worktree uses primary repo session"

if run_go missing-branch >"$TMP_DIR/unknown-out" 2>"$TMP_DIR/unknown-err"; then
    fail "unknown branch should fail"
fi
unknown_error="$(<"$TMP_DIR/unknown-err")"
assert_contains "$unknown_error" "No worktree found for branch 'missing-branch'" "unknown branch error"
assert_contains "$unknown_error" "grove pick" "unknown branch recovery"

: > "$ZELLIJ_STATE"
: > "$ZELLIJ_LOG"
run_go feat/nav >/dev/null
log="$(<"$ZELLIJ_LOG")"
assert_contains "$log" "--new-session-with-layout" "missing session is created"
layout="$(</tmp/grove-layout-demo.kdl)"
assert_contains "$layout" 'tab name="feat/nav" focus=true' "new session focuses requested branch"

printf 'go navigation tests passed\n'
