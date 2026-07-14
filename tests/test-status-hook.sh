#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d /tmp/grove-status-hook-XXXXXXXX)"
trap 'rm -rf "$TMP_DIR"' EXIT

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    exit 1
}

wait_for_exit() {
    local pid="$1"
    local label="$2"
    local attempt
    for attempt in $(seq 1 40); do
        if ! kill -0 "$pid" 2>/dev/null; then
            wait "$pid"
            return 0
        fi
        sleep 0.05
    done
    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
    fail "$label did not exit"
}

REPO_DIR="$TMP_DIR/demo"
STATUS_BIN="$TMP_DIR/grove-status"
STATUS_LOG="$TMP_DIR/status.log"
mkdir -p "$REPO_DIR"

git -C "$REPO_DIR" init -q
git -C "$REPO_DIR" config user.name "Grove Tests"
git -C "$REPO_DIR" config user.email "grove@example.com"
touch "$REPO_DIR/README.md"
git -C "$REPO_DIR" add README.md
git -C "$REPO_DIR" commit -qm "test fixture"

cat > "$STATUS_BIN" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" > "$STATUS_LOG"
printf 'compact status\n'
EOF
chmod +x "$STATUS_BIN"

(
    cd "$REPO_DIR"
    GROVE_STATUS_BIN="$STATUS_BIN" STATUS_LOG="$STATUS_LOG" \
        bash "$ROOT_DIR/git-worktree.sh" status --json . >"$TMP_DIR/dev-output"
) &
pid=$!
wait_for_exit "$pid" "status binary hook"
[[ "$(<"$TMP_DIR/dev-output")" == "compact status" ]] || fail "status hook output was not forwarded"
[[ "$(<"$STATUS_LOG")" == "status --json ." ]] || fail "status hook arguments were not forwarded"

(
    cd "$REPO_DIR"
    env -u GROVE_STATUS_BIN bash "$ROOT_DIR/git-worktree.sh" status . >"$TMP_DIR/fallback-output"
) &
pid=$!
wait_for_exit "$pid" "fallback status"
grep -q "Git Worktrees:" "$TMP_DIR/fallback-output" || fail "fallback did not render worktree status: $(<"$TMP_DIR/fallback-output")"
grep -q "demo" "$TMP_DIR/fallback-output" || fail "fallback did not identify the repository"

printf 'status hook tests passed\n'
