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

git -C "$REPO_DIR" worktree add -q -b feature/this-is-a-very-long-name-alpha "$TMP_DIR/demo-alpha"
git -C "$REPO_DIR" worktree add -q -b feature/this-is-a-very-long-name-beta "$TMP_DIR/demo-beta"
long_names="$(render --no-files | grep 'feature/this-is')"
[[ "$(printf '%s\n' "$long_names" | sort -u | wc -l | tr -d ' ')" == 2 ]] || fail "long branches should have distinct labels"

git -C "$REPO_DIR" worktree add -q -b feature/this-is-xx-very-long-name-alpha "$TMP_DIR/demo-xx"
git -C "$REPO_DIR" worktree add -q -b feature/this-is-yy-very-long-name-alpha "$TMP_DIR/demo-yy"
collision_output="$(render --no-files)"
[[ "$collision_output" == *'    feature/this-is-xx-very-long-name-alpha'* ]] || fail "first colliding branch needs its full name"
[[ "$collision_output" == *'    feature/this-is-yy-very-long-name-alpha'* ]] || fail "second colliding branch needs its full name"

LONG_REPO="$TMP_DIR/$(printf 'r%.0s' {1..75})"
mkdir -p "$LONG_REPO"
git -C "$LONG_REPO" init -q -b main
git -C "$LONG_REPO" commit -q --allow-empty -m init
printf 'x\n' > "$LONG_REPO/$(printf 'f%.0s' {1..90})"
while IFS= read -r line; do
    (( ${#line} <= 80 )) || fail "status line exceeds 80 columns: $line"
done < <(COLUMNS=80 NO_COLOR=1 GROVE_WORKTREE_BACKEND=git bash "$ROOT_DIR/worktree-status.sh" "$LONG_REPO")

printf 'status table tests passed\n'
