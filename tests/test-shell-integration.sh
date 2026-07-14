#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d /tmp/grove-shell-integration-XXXXXXXX)"
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

expected_commands="add agent agents cd diff exec go help info lock log ls main mv new open pick pr prune rename rm root run status sync tab unlock up which"
actual_commands="$(bash "$ROOT_DIR/launch-grove.sh" __commands | sort | tr '\n' ' ' | sed 's/ $//')"
[[ "$actual_commands" == "$expected_commands" ]] || fail "canonical commands: expected '$expected_commands', got '$actual_commands'"

completion_output="$({
    source "$ROOT_DIR/git-worktree-aliases.sh"
    COMP_WORDS=(grove "")
    COMP_CWORD=1
    _grove_complete
    printf '%s\n' "${COMPREPLY[@]}"
} 2>/dev/null)"
assert_contains "$completion_output" "go" "Bash completion includes canonical go verb"
assert_contains "$completion_output" "codex" "Bash completion preserves agent override candidates"

if rg -q 'git merge-base|git patch-id|git rev-list' "$ROOT_DIR/git-worktree-aliases.sh" "$ROOT_DIR/git-worktree-aliases.fish"; then
    fail "alias files should delegate worktree algorithms to git-worktree.sh"
fi

fish_source="$(<"$ROOT_DIR/git-worktree-aliases.fish")"
assert_contains "$fish_source" 'case cd' "Fish grove handles cd in the parent shell"
assert_contains "$fish_source" 'case main' "Fish grove handles main in the parent shell"
assert_contains "$fish_source" 'case pick' "Fish grove handles pick in the parent shell"
assert_contains "$fish_source" '__commands' "Fish completion uses canonical commands"

REPO_DIR="$TMP_DIR/demo"
WORKTREE_DIR="$TMP_DIR/feat-nav"
mkdir -p "$REPO_DIR"
git -C "$REPO_DIR" init -q
git -C "$REPO_DIR" config user.name "Grove Tests"
git -C "$REPO_DIR" config user.email "grove@example.com"
touch "$REPO_DIR/README.md"
git -C "$REPO_DIR" add README.md
git -C "$REPO_DIR" commit -qm "test fixture"
git -C "$REPO_DIR" worktree add -qb feat/nav "$WORKTREE_DIR"

actual_cwd="$({
    source "$ROOT_DIR/git-worktree-aliases.sh"
    cd "$REPO_DIR"
    grove cd feat/nav >/dev/null
    pwd
})"
expected_cwd="$(cd "$WORKTREE_DIR" && pwd -P)"
[[ "$actual_cwd" == "$expected_cwd" ]] || fail "grove cd changed to '$actual_cwd', want '$expected_cwd'"

printf 'shell integration tests passed\n'
