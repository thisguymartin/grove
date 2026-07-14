#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d /tmp/grove-installer-XXXXXXXX)"
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

new_case() {
    CASE_DIR="$TMP_DIR/$1"
    HOME_DIR="$CASE_DIR/home"
    FAKE_BIN="$CASE_DIR/bin"
    FAKE_LOG="$CASE_DIR/commands.log"
    GROVE_TEST_DIR="$CASE_DIR/grove"
    mkdir -p "$HOME_DIR" "$FAKE_BIN"
    : > "$FAKE_LOG"

    cat > "$FAKE_BIN/brew" <<'EOF'
#!/usr/bin/env bash
printf 'brew %s\n' "$*" >> "$FAKE_LOG"
if [[ "$*" == "install node" ]]; then
    cat > "$FAKE_BIN/npm" <<'NPMEOF'
#!/usr/bin/env bash
printf 'npm %s\n' "$*" >> "$FAKE_LOG"
NPMEOF
    chmod +x "$FAKE_BIN/npm"
fi
EOF
    chmod +x "$FAKE_BIN/brew"
}

run_install() {
    local agent="$1"
    HOME="$HOME_DIR" \
    XDG_CONFIG_HOME="$HOME_DIR/.config" \
    GROVE_DIR="$GROVE_TEST_DIR" \
    SHELL="/bin/zsh" \
    FAKE_BIN="$FAKE_BIN" \
    FAKE_LOG="$FAKE_LOG" \
    PATH="$FAKE_BIN:/usr/bin:/bin" \
        bash "$ROOT_DIR/install/install.sh" --local --agent "$agent" \
        </dev/null >"$CASE_DIR/stdout" 2>"$CASE_DIR/stderr"
}

if rg -q 'gemini-cli|claude-code|opencode|codex' "$ROOT_DIR/brewfile"; then
    fail "brewfile should contain only Grove core dependencies"
fi

new_case codex
run_install codex || fail "Codex install failed: $(<"$CASE_DIR/stderr")"
commands="$(<"$FAKE_LOG")"
assert_contains "$commands" "brew bundle --file=$GROVE_TEST_DIR/brewfile" "core dependencies"
assert_contains "$commands" "brew install --cask codex" "Codex package"
assert_not_contains "$commands" "claude-code" "Codex isolation"
assert_not_contains "$commands" "opencode" "Codex isolation"
assert_not_contains "$commands" "gemini" "Codex isolation"
[[ "$(<"$HOME_DIR/.config/grove/config")" == "default_ai=codex" ]] || fail "Codex default config"

new_case opencode
run_install opencode || fail "OpenCode install failed: $(<"$CASE_DIR/stderr")"
commands="$(<"$FAKE_LOG")"
assert_contains "$commands" "brew install anomalyco/tap/opencode" "OpenCode package"
assert_not_contains "$commands" "--cask codex" "OpenCode isolation"

new_case claude
run_install claude || fail "Claude install failed: $(<"$CASE_DIR/stderr")"
commands="$(<"$FAKE_LOG")"
assert_contains "$commands" "brew install --cask claude-code" "Claude package"
assert_not_contains "$commands" "--cask codex" "Claude isolation"

new_case gemini
run_install gemini || fail "Gemini install failed: $(<"$CASE_DIR/stderr")"
commands="$(<"$FAKE_LOG")"
assert_contains "$commands" "brew install node" "Gemini Node dependency"
assert_contains "$commands" "npm install -g @google/gemini-cli" "Gemini npm package"
assert_not_contains "$commands" "brew install gemini-cli" "deprecated Gemini formula"

new_case existing
cat > "$FAKE_BIN/codex" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$FAKE_BIN/codex"
run_install codex || fail "existing Codex selection failed"
commands="$(<"$FAKE_LOG")"
assert_not_contains "$commands" "brew install --cask codex" "existing Codex reinstall"
[[ "$(<"$HOME_DIR/.config/grove/config")" == "default_ai=codex" ]] || fail "existing Codex default config"

new_case none
run_install none || fail "no-agent install failed"
commands="$(<"$FAKE_LOG")"
assert_not_contains "$commands" "codex" "none isolation"
assert_not_contains "$commands" "opencode" "none isolation"
assert_not_contains "$commands" "claude" "none isolation"
assert_not_contains "$commands" "gemini" "none isolation"
[[ "$(<"$HOME_DIR/.config/grove/config")" == "default_ai=none" ]] || fail "none default config"

new_case reinstall
run_install codex || fail "initial install before default replacement failed"
run_install claude || fail "reinstall with replacement default failed"
[[ "$(<"$HOME_DIR/.config/grove/config")" == "default_ai=claude" ]] || fail "reinstall should replace default config"

new_case missing
if HOME="$HOME_DIR" XDG_CONFIG_HOME="$HOME_DIR/.config" GROVE_DIR="$GROVE_TEST_DIR" \
    SHELL="/bin/zsh" FAKE_BIN="$FAKE_BIN" FAKE_LOG="$FAKE_LOG" \
    PATH="$FAKE_BIN:/usr/bin:/bin" bash "$ROOT_DIR/install/install.sh" --local \
    </dev/null >"$CASE_DIR/stdout" 2>"$CASE_DIR/stderr"; then
    fail "non-interactive install without --agent should fail"
fi
[[ ! -e "$GROVE_TEST_DIR" ]] || fail "missing agent mutated install directory"
[[ ! -e "$HOME_DIR/.zshrc" ]] || fail "missing agent mutated shell config"
assert_contains "$(<"$CASE_DIR/stderr")" "--agent" "missing agent guidance"

new_case invalid
if run_install cursor; then
    fail "unsupported agent should fail"
fi
[[ ! -e "$GROVE_TEST_DIR" ]] || fail "invalid agent mutated install directory"
assert_contains "$(<"$CASE_DIR/stderr")" "Unsupported agent" "invalid agent guidance"

if command -v expect >/dev/null 2>&1; then
    new_case interactive
    export HOME_DIR FAKE_BIN FAKE_LOG GROVE_TEST_DIR ROOT_DIR CASE_DIR
    expect <<'EOF' >"$CASE_DIR/expect-stdout" 2>"$CASE_DIR/expect-stderr"
set timeout 15
spawn env HOME=$env(HOME_DIR) XDG_CONFIG_HOME=$env(HOME_DIR)/.config \
    GROVE_DIR=$env(GROVE_TEST_DIR) SHELL=/bin/zsh FAKE_BIN=$env(FAKE_BIN) \
    FAKE_LOG=$env(FAKE_LOG) PATH=$env(FAKE_BIN):/usr/bin:/bin \
    bash $env(ROOT_DIR)/install/install.sh --local
expect "Selection \[1-5\]:"
send "1\r"
expect eof
catch wait result
exit [lindex $result 3]
EOF
    [[ "$(<"$HOME_DIR/.config/grove/config")" == "default_ai=codex" ]] || fail "interactive Codex selection"
    if grep -q "alias gwt=" "$HOME_DIR/.zshrc"; then
        fail "installer should not add the legacy gwt alias"
    fi
fi

new_case uninstall
run_install none || fail "setup before uninstall failed"
printf 'n' | HOME="$HOME_DIR" XDG_CONFIG_HOME="$HOME_DIR/.config" GROVE_DIR="$GROVE_TEST_DIR" \
    SHELL="/bin/zsh" PATH="$FAKE_BIN:/usr/bin:/bin" \
    bash "$ROOT_DIR/install/install.sh" --uninstall >"$CASE_DIR/uninstall-stdout" 2>"$CASE_DIR/uninstall-stderr"
[[ ! -e "$HOME_DIR/.config/grove/config" ]] || fail "uninstall should remove Grove config"

printf 'installer tests passed\n'
