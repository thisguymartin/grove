#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d /tmp/grove-worktrees-lib-XXXXXXXX)"
trap 'rm -rf "$TMP_DIR"' EXIT
TMP_DIR="$(cd "$TMP_DIR" && pwd -P)"

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
unset GWT_WORKTREE_DIR

# shellcheck source=../lib/worktrees.sh
source "$ROOT_DIR/lib/worktrees.sh"

# Normal clone: main worktree, one linked branch worktree, one detached worktree.
NORMAL="$TMP_DIR/normal/demo"
mkdir -p "$NORMAL"
git -C "$NORMAL" init -q -b main
git -C "$NORMAL" commit -q --allow-empty -m init
git -C "$NORMAL" worktree add -q -b feat/x "$TMP_DIR/normal/demo-feat-x"
git -C "$NORMAL" worktree add -q --detach "$TMP_DIR/normal/demo-detached"
normal_head="$(git -C "$NORMAL" rev-parse HEAD)"

expected_main_row="$NORMAL"$'\t'"main"$'\t'"$normal_head"$'\t'"main"
expected_linked_rows="$TMP_DIR/normal/demo-detached"$'\t\t'"$normal_head"$'\t'$'\n'"$TMP_DIR/normal/demo-feat-x"$'\t'"feat/x"$'\t'"$normal_head"$'\t'

for cwd in "$NORMAL" "$TMP_DIR/normal/demo-feat-x" "$TMP_DIR/normal/demo-detached"; do
    label="normal from ${cwd##*/}"
    rows="$(cd "$cwd" && grove_worktrees)"
    assert_eq "$(head -n1 <<< "$rows")" "$expected_main_row" "$label: main row first"
    assert_eq "$(tail -n +2 <<< "$rows" | sort)" "$expected_linked_rows" "$label: linked rows"
    assert_eq "$(cd "$cwd" && grove_repo_root)" "$NORMAL" "$label: repo root"
    assert_eq "$(cd "$cwd" && grove_main_worktree)" "$NORMAL" "$label: main worktree"
    assert_eq "$(cd "$cwd" && grove_repo_name)" "demo" "$label: repo name"
    assert_eq "$(cd "$cwd" && grove_worktree_target feat/y)" "$TMP_DIR/normal/worktrees/demo/feat/y" "$label: new target"
    assert_eq "$(cd "$cwd" && grove_worktree_path feat/x)" "$TMP_DIR/normal/demo-feat-x" "$label: branch path"
    (cd "$cwd" && grove_repo_is_bare_layout) && fail "$label: reported a bare layout"
done

detached_fields="$(cd "$NORMAL" && grove_worktree_fields | while IFS=$'\037' read -r p b h f; do
    [[ -z "$b" ]] && printf '%s|%s|%s|%s\n' "$p" "$b" "$h" "$f"
done || true)"
assert_eq "$detached_fields" "$TMP_DIR/normal/demo-detached||$normal_head|" "detached row keeps its empty branch field"

if (cd "$NORMAL" && grove_worktree_path missing >/dev/null); then
    fail "missing branch should fail"
fi

# Bare layout: proj/.git is bare; main/ and feat-x/ are sibling worktrees.
git init -q -b main "$TMP_DIR/src"
git -C "$TMP_DIR/src" commit -q --allow-empty -m init
PROJ="$TMP_DIR/bare/proj"
git clone -q --bare "$TMP_DIR/src" "$PROJ/.git"
git -C "$PROJ" worktree add -q main main
git -C "$PROJ/main" worktree add -q ../feat-x -b feat/x
bare_head="$(git -C "$PROJ/main" rev-parse HEAD)"

expected_bare_rows="$PROJ/main"$'\t'"main"$'\t'"$bare_head"$'\t'"main"$'\n'"$PROJ/feat-x"$'\t'"feat/x"$'\t'"$bare_head"$'\t'

for cwd in "$PROJ/main" "$PROJ/feat-x" "$PROJ"; do
    label="bare from ${cwd#"$TMP_DIR"/bare/}"
    assert_eq "$(cd "$cwd" && grove_worktrees)" "$expected_bare_rows" "$label: rows"
    assert_eq "$(cd "$cwd" && grove_repo_root)" "$PROJ" "$label: repo root"
    assert_eq "$(cd "$cwd" && grove_main_worktree)" "$PROJ/main" "$label: main worktree"
    assert_eq "$(cd "$cwd" && grove_repo_name)" "proj" "$label: repo name"
    assert_eq "$(cd "$cwd" && grove_worktree_target feat/y)" "$PROJ/feat-y" "$label: new target"
    assert_eq "$(cd "$cwd" && grove_worktree_path feat/x)" "$PROJ/feat-x" "$label: branch path"
    (cd "$cwd" && grove_repo_is_bare_layout) || fail "$label: missed the bare layout"
done

printf 'worktrees lib tests passed\n'
