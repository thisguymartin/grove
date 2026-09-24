#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d /tmp/grove-worktree-backend-XXXXXXXX)"
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

assert_contains() {
    local haystack="$1"
    local needle="$2"
    local label="$3"
    [[ "$haystack" == *"$needle"* ]] || fail "$label: expected '$needle' in '$haystack'"
}

export GIT_AUTHOR_NAME="Grove Tests" GIT_AUTHOR_EMAIL="grove@example.com"
export GIT_COMMITTER_NAME="Grove Tests" GIT_COMMITTER_EMAIL="grove@example.com"
unset GWT_WORKTREE_DIR GWT_BASE_BRANCH GROVE_WORKTREE_BACKEND ZELLIJ ZELLIJ_SESSION_NAME

FAKE_BIN="$TMP_DIR/bin"
export WT_LOG="$TMP_DIR/wt.log"
mkdir -p "$FAKE_BIN"

# Fake worktrunk: log argv, then do the real git work so Grove can resolve the new path.
cat > "$FAKE_BIN/wt" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$WT_LOG"
dir="." verb="" create=false base="" branch=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        -C) dir="$2"; shift 2 ;;
        --config-set) shift 2 ;;
        -b) base="$2"; shift 2 ;;
        --create) create=true; shift ;;
        --no-cd) shift ;;
        switch|remove) verb="$1"; shift ;;
        *) branch="$1"; shift ;;
    esac
done
target="$(dirname "$(git -C "$dir" rev-parse --show-toplevel)")/wt-${branch//\//-}"
case "$verb" in
    switch)
        if $create; then
            git -C "$dir" worktree add -q "$target" -b "$branch" ${base:+"$base"}
        else
            git -C "$dir" worktree add -q "$target" "$branch"
        fi
        ;;
    remove)
        git -C "$dir" worktree remove "$target"
        ;;
esac
EOF
printf '#!/usr/bin/env bash\nexit 0\n' > "$FAKE_BIN/zellij"
chmod +x "$FAKE_BIN/wt" "$FAKE_BIN/zellij"

grove_in() {
    local cwd="$1"
    shift
    (cd "$cwd" && PATH="$FAKE_BIN:$PATH" bash "$ROOT_DIR/git-worktree.sh" "$@")
}

NORMAL="$TMP_DIR/normal/demo"
mkdir -p "$NORMAL"
git -C "$NORMAL" init -q -b main
git -C "$NORMAL" commit -q --allow-empty -m init

git init -q -b main "$TMP_DIR/src"
git -C "$TMP_DIR/src" commit -q --allow-empty -m init
PROJ="$TMP_DIR/bare/proj"
git clone -q --bare "$TMP_DIR/src" "$PROJ/.git"
git -C "$PROJ" worktree add -q main main

# Default backend with wt on PATH is worktrunk; wt runs from the main worktree.
: > "$WT_LOG"
output="$(grove_in "$NORMAL" new feat/z)"
assert_eq "$(<"$WT_LOG")" "-C $NORMAL switch --create --no-cd feat/z" "worktrunk new argv"
assert_contains "$output" "Worktree created: $TMP_DIR/normal/wt-feat-z (new branch: feat/z)" "worktrunk new resolves the created path"

: > "$WT_LOG"
GWT_BASE_BRANCH=main grove_in "$PROJ" new feat/based >/dev/null
assert_eq "$(<"$WT_LOG")" "-C $PROJ/main --config-set worktree-path=\"{{ repo_path }}/../{{ branch | sanitize }}\" switch --create --no-cd feat/based -b main" "worktrunk new from bare dir places worktrees beside main"

: > "$WT_LOG"
WORKTRUNK_WORKTREE_PATH='{{ repo_path }}/../x-{{ branch }}' grove_in "$PROJ" new feat/env >/dev/null
assert_eq "$(<"$WT_LOG")" "-C $PROJ/main switch --create --no-cd feat/env" "user worktree-path env wins over Grove's bare default"

mkdir -p "$TMP_DIR/wtcfg"
printf 'worktree-path = "{{ repo_path }}/../y-{{ branch }}"\n' > "$TMP_DIR/wtcfg/config.toml"
: > "$WT_LOG"
WORKTRUNK_CONFIG_PATH="$TMP_DIR/wtcfg/config.toml" grove_in "$PROJ" new feat/cfg >/dev/null
assert_eq "$(<"$WT_LOG")" "-C $PROJ/main switch --create --no-cd feat/cfg" "user config worktree-path wins over Grove's bare default"

git -C "$NORMAL" branch feat/existing
: > "$WT_LOG"
grove_in "$NORMAL" add feat/existing >/dev/null
assert_eq "$(<"$WT_LOG")" "-C $NORMAL switch --no-cd feat/existing" "worktrunk add argv"

: > "$WT_LOG"
grove_in "$NORMAL" rm feat/existing >/dev/null
assert_eq "$(<"$WT_LOG")" "-C $NORMAL remove feat/existing" "worktrunk rm argv"

# Forced git backend never calls wt and follows each layout's convention.
: > "$WT_LOG"
GROVE_WORKTREE_BACKEND=git grove_in "$PROJ/main" new feat/z >/dev/null
[[ -d "$PROJ/feat-z" ]] || fail "git backend should create $PROJ/feat-z in the bare layout"
GROVE_WORKTREE_BACKEND=git grove_in "$NORMAL" new feat/y >/dev/null
[[ -d "$TMP_DIR/normal/worktrees/demo/feat/y" ]] || fail "git backend should create ../worktrees/demo/feat/y in the normal layout"
[[ ! -s "$WT_LOG" ]] || fail "git backend invoked wt: $(<"$WT_LOG")"

ls_output="$(GROVE_WORKTREE_BACKEND=git grove_in "$NORMAL" ls)"
assert_contains "$(head -n1 <<< "$ls_output")" "demo · git · " "ls names the backend"

if GROVE_WORKTREE_BACKEND=bogus grove_in "$NORMAL" new feat/bad >/dev/null 2>"$TMP_DIR/stderr"; then
    fail "invalid backend should fail"
fi
assert_eq "$(<"$TMP_DIR/stderr")" "Error: GROVE_WORKTREE_BACKEND must be git or worktrunk" "invalid backend error"

printf 'worktree backend tests passed\n'
