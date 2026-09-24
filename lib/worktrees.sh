#!/usr/bin/env bash
# Worktree inventory shared by every Grove script.
#
# A worktree row is one line: path<TAB>branch<TAB>head<TAB>flags
#   branch  short name, empty when detached
#   head    full commit sha
#   flags   comma-joined subset of main,locked
# The bare repository of a bare layout is never a row. The main row prints first.
# Every function takes an optional path (default: $PWD) inside the repository,
# which may be the main worktree, a linked worktree, or the bare directory.

grove_repo_common_dir() {
    git -C "${1:-$PWD}" rev-parse --path-format=absolute --git-common-dir 2>/dev/null
}

grove_repo_is_bare_layout() {
    [[ "$(git -C "${1:-$PWD}" config --bool core.bare 2>/dev/null)" == "true" ]]
}

grove_worktrees() {
    local repo="${1:-$PWD}" candidates="" default_branch=""
    if grove_repo_is_bare_layout "$repo"; then
        default_branch="$(git -C "$repo" symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null)" || true
        candidates="${default_branch#origin/} main master"
    fi
    git -C "$repo" worktree list --porcelain | awk -v candidates="$candidates" '
        function flush() {
            if (wt != "" && !bare) { n++; p[n] = wt; b[n] = br; h[n] = hd; l[n] = lk }
            wt = br = hd = ""; bare = lk = 0
        }
        function row(i, is_main,   f) {
            f = is_main ? "main" : ""
            if (l[i]) f = f (f == "" ? "" : ",") "locked"
            printf "%s\t%s\t%s\t%s\n", p[i], b[i], h[i], f
        }
        /^worktree / { flush(); wt = substr($0, 10) }
        /^HEAD /     { hd = substr($0, 6) }
        /^branch /   { br = substr($0, 8); sub(/^refs\/heads\//, "", br) }
        $0 == "bare" { bare = 1 }
        /^locked/    { lk = 1 }
        END {
            flush()
            if (n == 0) exit
            m = 1
            k = split(candidates, c, " ")
            for (i = 1; i <= k && m == 1; i++)
                for (j = 1; j <= n; j++)
                    if (b[j] == c[i]) { m = j; break }
            row(m, 1)
            for (j = 1; j <= n; j++) if (j != m) row(j, 0)
        }
    '
}

# Rows with \037 separators: `read` treats tab as whitespace and would merge
# the empty branch field of a detached row. Read with IFS=$'\037'.
grove_worktree_fields() {
    grove_worktrees "$@" | tr '\t' '\037'
}

grove_main_worktree() {
    grove_worktrees "$@" | awk -F'\t' '$4 ~ /(^|,)main(,|$)/ { print $1; exit }'
}

grove_repo_root() {
    local repo="${1:-$PWD}" common
    if grove_repo_is_bare_layout "$repo"; then
        common="$(grove_repo_common_dir "$repo")" || return 1
        dirname "$common"
    else
        grove_main_worktree "$repo"
    fi
}

grove_repo_name() {
    local root
    root="$(grove_repo_root "$@")" || return 1
    basename "$root"
}

grove_worktree_path() {
    local branch="${1:?branch required}"
    grove_worktrees "${2:-$PWD}" | awk -F'\t' -v br="$branch" '
        $2 == br { print $1; found = 1; exit }
        END { exit !found }
    '
}

grove_default_worktree_dir() {
    local repo="${1:-$PWD}" root
    root="$(grove_repo_root "$repo")" || return 1
    if grove_repo_is_bare_layout "$repo"; then
        printf '%s\n' "$root"
    else
        printf '%s\n' "${GWT_WORKTREE_DIR:-$(dirname "$root")/worktrees/$(basename "$root")}"
    fi
}

# Bare layouts flatten "/" to "-" to match worktrunk's sanitize filter.
grove_worktree_target() {
    local branch="${1:?branch required}" repo="${2:-$PWD}" dir
    dir="$(grove_default_worktree_dir "$repo")" || return 1
    if grove_repo_is_bare_layout "$repo"; then
        printf '%s/%s\n' "$dir" "${branch//\//-}"
    else
        printf '%s/%s\n' "$dir" "$branch"
    fi
}
