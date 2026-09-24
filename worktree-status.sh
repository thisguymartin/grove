#!/usr/bin/env bash
# worktree-status.sh — one compact table of every worktree in a repository.
#
# Usage:
#   ./worktree-status.sh [--no-files] [path]
#
# Rows needing attention (dirty, behind upstream, or detached) come first and
# carry a "!" marker. Color is used only on a terminal without NO_COLOR.
# Width follows $COLUMNS (default 80).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/worktrees.sh
source "$SCRIPT_DIR/lib/worktrees.sh"
# shellcheck source=lib/backend.sh
source "$SCRIPT_DIR/lib/backend.sh"

SHOW_FILES=true
REPO_PATH=""
for arg in "$@"; do
    case "$arg" in
        --no-files) SHOW_FILES=false ;;
        *) REPO_PATH="$arg" ;;
    esac
done
REPO_PATH="${REPO_PATH:-$(pwd)}"

grove_repo_common_dir "$REPO_PATH" >/dev/null || {
    echo "Error: not a git repository: $REPO_PATH"
    exit 1
}
BACKEND="$(grove_worktree_backend)" || exit 1
WIDTH="${COLUMNS:-80}"
MAX_FILES=5

BOLD='' DIM='' RED='' GREEN='' YELLOW='' CYAN='' RESET=''
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
    BOLD=$'\033[1m' DIM=$'\033[2m' RED=$'\033[31m' GREEN=$'\033[32m'
    YELLOW=$'\033[33m' CYAN=$'\033[36m' RESET=$'\033[0m'
fi

# printf pads by bytes; ${#s} counts characters, so ↑ ↓ … stay aligned.
pad() {
    local text="$1" width="$2"
    printf '%s%*s' "$text" $((width - ${#text})) ''
}

truncate() {
    local text="$1" width="$2"
    if (( ${#text} > width )); then
        text="${text:0:width-1}…"
    fi
    printf '%s' "$text"
}

# Rank orders the table: 0 dirty, 1 behind, 2 detached, 3 main, 4 the rest.
names=() ranks=() is_main=() states=() syncs=() commits=() paths=()
while IFS=$'\037' read -r path branch head flags; do
    changed=0
    changes="$(git -C "$path" status --porcelain 2>/dev/null || true)"
    if [[ -n "$changes" ]]; then
        changed="$(printf '%s\n' "$changes" | wc -l | tr -d ' ')"
    fi

    ahead=0 behind=0
    if [[ -n "$branch" ]] && upstream="$(git -C "$path" rev-parse --abbrev-ref "${branch}@{upstream}" 2>/dev/null)"; then
        read -r ahead behind < <(git -C "$path" rev-list --left-right --count "${branch}...${upstream}" 2>/dev/null || echo "0 0")
    fi
    sync=""
    if (( ahead > 0 )); then sync="↑$ahead"; fi
    if (( behind > 0 )); then sync="${sync:+$sync }↓$behind"; fi

    main=false
    if [[ "$flags" == *main* ]]; then main=true; fi

    if (( changed > 0 )); then rank=0
    elif (( behind > 0 )); then rank=1
    elif [[ -z "$branch" ]]; then rank=2
    elif $main; then rank=3
    else rank=4
    fi

    name="$(truncate "${branch:-${head:0:7}}" 24)"
    if $main; then name="$name *"; fi
    state="clean"
    if (( changed > 0 )); then state="$changed changed"; fi

    names+=("$name")
    ranks+=("$rank")
    is_main+=("$main")
    states+=("$state")
    syncs+=("$sync")
    commits+=("${head:0:7} $(git -C "$path" log -1 --format=%s "$head" 2>/dev/null || true)")
    paths+=("$path")
done < <(grove_worktree_fields "$REPO_PATH")

count=${#names[@]}
noun="worktrees"
if (( count == 1 )); then noun="worktree"; fi
printf '%s%s%s · %s · %d %s · %s\n' "$BOLD" "$(grove_repo_name "$REPO_PATH")" "$RESET" \
    "$BACKEND" "$count" "$noun" "$(date '+%H:%M')"
if (( count == 0 )); then exit 0; fi

name_w=0 state_w=0 sync_w=0
for i in "${!names[@]}"; do
    if (( ${#names[i]} > name_w )); then name_w=${#names[i]}; fi
    if (( ${#states[i]} > state_w )); then state_w=${#states[i]}; fi
    if (( ${#syncs[i]} > sync_w )); then sync_w=${#syncs[i]}; fi
done
sync_col=0
if (( sync_w > 0 )); then sync_col=$((sync_w + 2)); fi
commit_w=$((WIDTH - 2 - name_w - 2 - state_w - 2 - sync_col))
if (( commit_w < 12 )); then commit_w=12; fi

order="$(for i in "${!names[@]}"; do printf '%s\t%s\t%s\n' "${ranks[i]}" "${names[i]}" "$i"; done \
    | sort -t$'\t' -k1,1n -k2,2 | cut -f3)"

while IFS= read -r i; do
    mark=" "
    if (( ranks[i] < 3 )); then mark="!"; fi
    name_color="$BOLD"
    if [[ "${is_main[i]}" == true ]]; then name_color="$CYAN$BOLD"; fi
    state_color="$GREEN"
    if [[ "${states[i]}" != clean ]]; then state_color="$YELLOW"; fi

    line="$RED$mark$RESET $name_color$(pad "${names[i]}" "$name_w")$RESET  "
    line+="$state_color$(pad "${states[i]}" "$state_w")$RESET  "
    if (( sync_col > 0 )); then line+="$YELLOW$(pad "${syncs[i]}" "$sync_w")$RESET  "; fi
    line+="$DIM$(truncate "${commits[i]}" "$commit_w")$RESET"
    printf '%s\n' "$line"

    if $SHOW_FILES && (( ranks[i] == 0 )); then
        changes="$(git -C "${paths[i]}" status --porcelain 2>/dev/null || true)"
        total="$(printf '%s\n' "$changes" | wc -l | tr -d ' ')"
        while IFS= read -r entry; do
            code="${entry:0:2}"
            printf '    %s%-2s%s %s\n' "$DIM" "${code// /}" "$RESET" "${entry:3}"
        done < <(printf '%s\n' "$changes" | head -n "$MAX_FILES")
        if (( total > MAX_FILES )); then
            printf '    %s... and %d more%s\n' "$DIM" $((total - MAX_FILES)) "$RESET"
        fi
    fi
done <<< "$order"
