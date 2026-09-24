#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d /tmp/grove-status-table-XXXXXXXX)"
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

export GIT_AUTHOR_NAME="Grove Tests" GIT_AUTHOR_EMAIL="grove@example.com"
export GIT_COMMITTER_NAME="Grove Tests" GIT_COMMITTER_EMAIL="grove@example.com"

REPO_DIR="$TMP_DIR/demo"
mkdir -p "$REPO_DIR"
git -C "$REPO_DIR" init -q -b main
git -C "$REPO_DIR" commit -q --allow-empty -m "init"
git -C "$REPO_DIR" worktree add -q -b feat/clean "$TMP_DIR/demo-clean"
git -C "$REPO_DIR" worktree add -q -b feat/dirty "$TMP_DIR/demo-dirty"
for i in 1 2 3 4 5 6 7; do
    printf 'x\n' > "$TMP_DIR/demo-dirty/file$i.txt"
done
head="$(git -C "$REPO_DIR" rev-parse --short=7 HEAD)"

render() {
    (cd "$REPO_DIR" && COLUMNS=80 GROVE_WORKTREE_BACKEND=git bash "$ROOT_DIR/worktree-status.sh" "$@") \
        | sed $'s/\x1b\\[[0-9;]*m//g'
}

output="$(render)"
header="$(sed -n 1p <<< "$output")"
[[ "$header" =~ ^demo\ ·\ git\ ·\ 3\ worktrees\ ·\ [0-9]{2}:[0-9]{2}$ ]] || fail "header: got '$header'"

expected_table="! feat/dirty  7 changed  $head init
    ?? file1.txt
    ?? file2.txt
    ?? file3.txt
    ?? file4.txt
    ?? file5.txt
    ... and 2 more
  main *      clean      $head init
  feat/clean  clean      $head init"
assert_eq "$(tail -n +2 <<< "$output")" "$expected_table" "status table"

expected_compact="! feat/dirty  7 changed  $head init
  main *      clean      $head init
  feat/clean  clean      $head init"
assert_eq "$(render --no-files | tail -n +2)" "$expected_compact" "--no-files drops file lines"

ls_output="$(cd "$REPO_DIR" && GROVE_WORKTREE_BACKEND=git bash "$ROOT_DIR/git-worktree.sh" ls | tail -n +2)"
assert_eq "$ls_output" "$expected_compact" "grove ls uses the same renderer"

printf 'status table tests passed\n'
