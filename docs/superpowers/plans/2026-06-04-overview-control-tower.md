# Overview Control Tower Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a compact, repo-scoped Overview dashboard for Grove that shows actionable worktree, PR/CI, AI, stash, and resource status at a glance.

**Architecture:** Add a new `overview-status.sh` renderer that collects raw state directly from `git`, optional `gh`, process CWD, and local resource commands. Keep existing detailed scripts as secondary panes. Update the Zellij Overview layout to make compact status the primary pane and keep detail panes stacked/suspended.

**Tech Stack:** Bash, Git worktrees, GitHub CLI, Zellij KDL layouts, shell tests.

---

## File Structure

- Create `overview-status.sh`: compact Overview renderer. One responsibility: gather repo-scoped state and print compact terminal output.
- Create `tests/test-overview-status.sh`: shell tests for compact renderer using temporary git repos/worktrees and stubbed `gh`/process/resource behavior through environment overrides.
- Modify `layouts/workspace.kdl.template`: put `overview-status.sh` in the primary Overview pane and move existing detailed scripts into a secondary stack.
- Modify `launch-worktrees.sh`: render Overview detail panes consistently and stop making PR/CI visibility depend only on eager Overview panes.
- Modify `resource-monitor.sh`: guard memory percentage when total memory is unavailable or zero.
- Modify `tests/test-launch-layout.sh`: assert compact Overview wiring in generated KDL.
- Modify `docs/architecture.md`: document compact Overview and detailed panes.
- Modify `README.md`: update one-line Overview description.

## Task 1: Add Compact Overview Git/Stash Core

**Files:**
- Create: `overview-status.sh`
- Create: `tests/test-overview-status.sh`

- [ ] **Step 1: Write failing tests for compact git rows**

Create `tests/test-overview-status.sh` with this content:

```bash
#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    exit 1
}

assert_contains() {
    local haystack="$1"
    local needle="$2"
    local label="$3"

    if [[ "$haystack" != *"$needle"* ]]; then
        printf 'OUTPUT:\n%s\n' "$haystack" >&2
        fail "$label: expected to find '$needle'"
    fi
}

assert_not_contains() {
    local haystack="$1"
    local needle="$2"
    local label="$3"

    if [[ "$haystack" == *"$needle"* ]]; then
        printf 'OUTPUT:\n%s\n' "$haystack" >&2
        fail "$label: did not expect '$needle'"
    fi
}

create_repo() {
    local repo="$1"
    mkdir -p "$repo"
    git -C "$repo" init -q
    git -C "$repo" config user.email "test@example.com"
    git -C "$repo" config user.name "Test User"
    printf 'root\n' > "$repo/README.md"
    git -C "$repo" add README.md
    git -C "$repo" commit -q -m "initial commit"
    git -C "$repo" branch -m main
}

tmp_dir="$(mktemp -d /tmp/grove-overview-test-XXXXXXXX)"
trap 'rm -rf "$tmp_dir"' EXIT

repo="$tmp_dir/repo"
create_repo "$repo"

git -C "$repo" worktree add -q -b feat/dirty "$tmp_dir/feat-dirty"
printf 'dirty\n' > "$tmp_dir/feat-dirty/dirty.txt"

output="$(GROVE_OVERVIEW_NO_COLOR=1 GROVE_OVERVIEW_NO_GH=1 GROVE_OVERVIEW_NO_AI=1 GROVE_OVERVIEW_NO_RESOURCE=1 bash "$ROOT_DIR/overview-status.sh" "$repo")"

assert_contains "$output" "Grove Overview: repo" "header"
assert_contains "$output" "2 worktrees" "worktree count"
assert_contains "$output" "1 needs action" "needs action count"
assert_contains "$output" "Needs Action" "needs action section"
assert_contains "$output" "feat/dirty" "dirty branch in needs action"
assert_contains "$output" "1 dirty file" "dirty count singular"
assert_contains "$output" "Worktrees" "worktrees section"
assert_contains "$output" "main" "main row"
assert_contains "$output" "clean" "clean state"
assert_contains "$output" "feat/dirty" "dirty row"
assert_contains "$output" "dirty:1" "dirty state"
assert_contains "$output" "PR/CI disabled" "disabled gh state"
assert_contains "$output" "idle" "ai disabled fallback"
assert_contains "$output" "System" "system section"
assert_contains "$output" "stashes 0" "stash count"
assert_not_contains "$output" "$tmp_dir/feat-dirty" "compact output hides absolute worktree path"

full_output="$(GROVE_OVERVIEW_NO_COLOR=1 GROVE_OVERVIEW_NO_GH=1 GROVE_OVERVIEW_NO_AI=1 GROVE_OVERVIEW_NO_RESOURCE=1 bash "$ROOT_DIR/overview-status.sh" --full "$repo")"
assert_contains "$full_output" "$tmp_dir/feat-dirty" "full mode shows path"
assert_contains "$full_output" "dirty.txt" "full mode shows changed file"

printf 'overview status tests passed\n'
```

- [ ] **Step 2: Run tests to verify failure**

Run:

```bash
bash tests/test-overview-status.sh
```

Expected:

```text
bash: /Users/thisguymartin/personal-workspace/grove/overview-status.sh: No such file or directory
```

- [ ] **Step 3: Create minimal compact renderer**

Create `overview-status.sh` with this content:

```bash
#!/usr/bin/env bash
# overview-status.sh - Compact Grove Overview control tower

set -euo pipefail

FULL_MODE=false
REPO_PATH=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --full)
            FULL_MODE=true
            shift
            ;;
        --help|-h)
            cat <<'USAGE'
Usage:
  overview-status.sh [--full] [repo-path]

Shows compact repo-scoped worktree status for Grove's Overview tab.
USAGE
            exit 0
            ;;
        *)
            REPO_PATH="$1"
            shift
            ;;
    esac
done

REPO_PATH="${REPO_PATH:-$(pwd)}"
REPO_PATH=$(git -C "$REPO_PATH" rev-parse --show-toplevel 2>/dev/null) || {
    printf 'Error: not a git repository: %s\n' "$REPO_PATH" >&2
    exit 1
}

REPO_NAME=$(basename "$REPO_PATH")

if [[ "${GROVE_OVERVIEW_NO_COLOR:-}" == "1" ]]; then
    BOLD=''
    GREEN=''
    YELLOW=''
    RED=''
    CYAN=''
    DIM=''
    RESET=''
else
    BOLD='\033[1m'
    GREEN='\033[32m'
    YELLOW='\033[33m'
    RED='\033[31m'
    CYAN='\033[36m'
    DIM='\033[2m'
    RESET='\033[0m'
fi

WORKTREE_PATHS=()
WORKTREE_BRANCHES=()
WORKTREE_HEADS=()

load_worktrees() {
    local wt_path="" wt_branch="" wt_head=""

    while IFS= read -r line; do
        case "$line" in
            worktree\ *) wt_path="${line#worktree }" ;;
            branch\ *) wt_branch="${line#branch }" ;;
            HEAD\ *) wt_head="${line#HEAD }" ;;
            detached) wt_branch="" ;;
            "")
                if [[ -n "$wt_path" ]]; then
                    WORKTREE_PATHS+=("$wt_path")
                    WORKTREE_BRANCHES+=("$wt_branch")
                    WORKTREE_HEADS+=("$wt_head")
                    wt_path=""
                    wt_branch=""
                    wt_head=""
                fi
                ;;
        esac
    done < <(git -C "$REPO_PATH" worktree list --porcelain)

    if [[ -n "$wt_path" ]]; then
        WORKTREE_PATHS+=("$wt_path")
        WORKTREE_BRANCHES+=("$wt_branch")
        WORKTREE_HEADS+=("$wt_head")
    fi
}

display_branch() {
    local branch="$1" head="$2"
    if [[ -n "$branch" ]]; then
        printf '%s' "${branch#refs/heads/}"
    else
        printf '%s' "${head:0:7}"
    fi
}

plural() {
    local count="$1" singular="$2" plural_word="$3"
    if [[ "$count" -eq 1 ]]; then
        printf '%s %s' "$count" "$singular"
    else
        printf '%s %s' "$count" "$plural_word"
    fi
}

git_state_for_path() {
    local path="$1" branch="$2"
    local changes change_count state upstream ab ahead behind

    changes=$(git -C "$path" status --porcelain 2>/dev/null || true)
    if [[ -n "$changes" ]]; then
        change_count=$(printf '%s\n' "$changes" | wc -l | tr -d ' ')
        state="dirty:${change_count}"
    else
        change_count=0
        state="clean"
    fi

    if [[ -n "$branch" ]]; then
        local branch_short="${branch#refs/heads/}"
        upstream=$(git -C "$path" rev-parse --abbrev-ref "${branch_short}@{upstream}" 2>/dev/null || true)
        if [[ -n "$upstream" ]]; then
            ab=$(git -C "$path" rev-list --left-right --count "${branch_short}...${upstream}" 2>/dev/null || true)
            if [[ -n "$ab" ]]; then
                ahead=$(printf '%s\n' "$ab" | awk '{print $1}')
                behind=$(printf '%s\n' "$ab" | awk '{print $2}')
                if [[ "${ahead:-0}" -gt 0 && "${behind:-0}" -gt 0 ]]; then
                    state="${state} ↑${ahead}↓${behind}"
                elif [[ "${ahead:-0}" -gt 0 ]]; then
                    state="${state} ↑${ahead}"
                elif [[ "${behind:-0}" -gt 0 ]]; then
                    state="${state} ↓${behind}"
                fi
            fi
        fi
    fi

    printf '%s' "$state"
}

gh_state_for_branch() {
    if [[ "${GROVE_OVERVIEW_NO_GH:-}" == "1" ]]; then
        printf 'PR/CI disabled'
    elif ! command -v gh >/dev/null 2>&1; then
        printf 'gh missing'
    elif ! gh auth status >/dev/null 2>&1; then
        printf 'gh auth needed'
    else
        printf 'no PR'
    fi
}

ai_state_for_path() {
    if [[ "${GROVE_OVERVIEW_NO_AI:-}" == "1" ]]; then
        printf 'idle'
    else
        printf 'idle'
    fi
}

resource_state() {
    if [[ "${GROVE_OVERVIEW_NO_RESOURCE:-}" == "1" ]]; then
        printf 'resources disabled'
    else
        printf 'resources unknown'
    fi
}

stash_count() {
    git -C "$REPO_PATH" stash list 2>/dev/null | sed '/^[[:space:]]*$/d' | wc -l | tr -d ' '
}

load_worktrees

needs_action=()
rows=()

for i in "${!WORKTREE_PATHS[@]}"; do
    path="${WORKTREE_PATHS[$i]}"
    branch="${WORKTREE_BRANCHES[$i]}"
    head="${WORKTREE_HEADS[$i]}"
    name="$(display_branch "$branch" "$head")"
    git_state="$(git_state_for_path "$path" "$branch")"
    pr_state="$(gh_state_for_branch "$name")"
    ai_state="$(ai_state_for_path "$path")"
    next="-"

    if [[ "$git_state" == dirty:* || "$git_state" == *" dirty:"* ]]; then
        dirty_count="${git_state#dirty:}"
        dirty_count="${dirty_count%% *}"
        needs_action+=("$name|$(plural "$dirty_count" "dirty file" "dirty files")|git status -sb")
        next="review changes"
    elif [[ "$pr_state" == "no PR" && "$name" != "main" && "$name" != "master" ]]; then
        next="push/open PR"
    fi

    rows+=("$name|$git_state|$pr_state|$ai_state|$next|$path")
done

printf '%bGrove Overview:%b %s  %s  %s  updated %s\n\n' \
    "$BOLD$CYAN" "$RESET" "$REPO_NAME" \
    "$(plural "${#WORKTREE_PATHS[@]}" "worktree" "worktrees")" \
    "$(plural "${#needs_action[@]}" "needs action" "needs action")" \
    "$(date '+%H:%M')"

printf '%bNeeds Action%b\n' "$BOLD" "$RESET"
if [[ "${#needs_action[@]}" -eq 0 ]]; then
    printf '  %bnone%b\n' "$GREEN" "$RESET"
else
    for item in "${needs_action[@]}"; do
        IFS='|' read -r name reason next <<< "$item"
        printf '  %-24s %-18s next: %s\n' "$name" "$reason" "$next"
    done
fi

printf '\n%bWorktrees%b\n' "$BOLD" "$RESET"
printf '  %-24s %-16s %-16s %-10s %s\n' "BRANCH" "GIT" "PR/CI" "AI" "NEXT"
for row in "${rows[@]}"; do
    IFS='|' read -r name git_state pr_state ai_state next path <<< "$row"
    printf '  %-24s %-16s %-16s %-10s %s\n' "$name" "$git_state" "$pr_state" "$ai_state" "$next"
    if $FULL_MODE; then
        printf '    %bpath:%b %s\n' "$DIM" "$RESET" "$path"
        changes=$(git -C "$path" status --short 2>/dev/null || true)
        if [[ -n "$changes" ]]; then
            while IFS= read -r change; do
                [[ -n "$change" ]] && printf '    %s\n' "$change"
            done <<< "$changes"
        fi
    fi
done

printf '\n%bSystem%b\n' "$BOLD" "$RESET"
printf '  %s  agents %s active  stashes %s\n' "$(resource_state)" "0" "$(stash_count)"
```

- [ ] **Step 4: Make renderer executable**

Run:

```bash
chmod +x overview-status.sh
```

Expected: no output.

- [ ] **Step 5: Run tests to verify pass**

Run:

```bash
bash tests/test-overview-status.sh
```

Expected:

```text
overview status tests passed
```

- [ ] **Step 6: Commit Task 1**

Run:

```bash
git add overview-status.sh tests/test-overview-status.sh
git commit -m "feat: add compact overview status core" -m "Add a repo-scoped Overview renderer that summarizes worktree state without showing paths or verbose detail by default." -m "- Parse git worktrees directly from porcelain output" -m "- Render needs-action, worktree, and system sections" -m "- Add shell coverage for clean, dirty, compact, and full modes"
```

## Task 2: Add GitHub PR/CI Summary

**Files:**
- Modify: `overview-status.sh`
- Modify: `tests/test-overview-status.sh`

- [ ] **Step 1: Add failing GitHub tests**

Append this test block before the final `printf 'overview status tests passed\n'` line in `tests/test-overview-status.sh`:

```bash
fake_bin="$tmp_dir/fake-bin"
mkdir -p "$fake_bin"
cat > "$fake_bin/gh" <<'GH'
#!/usr/bin/env bash
set -euo pipefail

if [[ "$1 $2" == "auth status" ]]; then
    exit 0
fi

if [[ "$1 $2" == "pr list" ]]; then
    cat <<'JSON'
[
  {
    "number": 42,
    "title": "Feature dirty",
    "headRefName": "feat/dirty",
    "isDraft": false,
    "reviewDecision": "REVIEW_REQUIRED",
    "statusCheckRollup": [
      {"conclusion": "FAILURE", "status": "COMPLETED"}
    ],
    "additions": 3,
    "deletions": 1
  }
]
JSON
    exit 0
fi

printf 'unexpected gh args: %s\n' "$*" >&2
exit 1
GH
chmod +x "$fake_bin/gh"

gh_output="$(PATH="$fake_bin:$PATH" GROVE_OVERVIEW_NO_COLOR=1 GROVE_OVERVIEW_NO_AI=1 GROVE_OVERVIEW_NO_RESOURCE=1 bash "$ROOT_DIR/overview-status.sh" "$repo")"
assert_contains "$gh_output" "#42 fail" "github pr summary"
assert_contains "$gh_output" "review" "github review state"
assert_contains "$gh_output" "CI failed" "failed check needs action"
assert_contains "$gh_output" "next: gh pr checks feat/dirty" "failed check next action"
```

- [ ] **Step 2: Run test to verify failure**

Run:

```bash
bash tests/test-overview-status.sh
```

Expected:

```text
FAIL: github pr summary: expected to find '#42 fail'
```

- [ ] **Step 3: Add one-shot PR lookup and formatter**

In `overview-status.sh`, replace the current `gh_state_for_branch()` function with this implementation and add the global `PR_JSON` initialization before the `load_worktrees` call:

```bash
PR_JSON=""
GH_STATUS="unknown"

load_pr_json() {
    if [[ "${GROVE_OVERVIEW_NO_GH:-}" == "1" ]]; then
        GH_STATUS="disabled"
        PR_JSON="[]"
    elif ! command -v gh >/dev/null 2>&1; then
        GH_STATUS="missing"
        PR_JSON="[]"
    elif ! gh auth status >/dev/null 2>&1; then
        GH_STATUS="auth"
        PR_JSON="[]"
    else
        GH_STATUS="ok"
        PR_JSON=$(cd "$REPO_PATH" && gh pr list \
            --json number,title,headRefName,isDraft,reviewDecision,statusCheckRollup,additions,deletions \
            --limit 50 2>/dev/null || printf '[]')
    fi
}

gh_state_for_branch() {
    local branch="$1"

    case "$GH_STATUS" in
        disabled) printf 'PR/CI disabled'; return ;;
        missing) printf 'gh missing'; return ;;
        auth) printf 'gh auth needed'; return ;;
    esac

    python3 - "$branch" "$PR_JSON" <<'PY'
import json
import sys

branch = sys.argv[1]
try:
    prs = json.loads(sys.argv[2])
except json.JSONDecodeError:
    prs = []

match = next((pr for pr in prs if pr.get("headRefName") == branch), None)
if not match:
    print("no PR")
    raise SystemExit

checks = match.get("statusCheckRollup") or []
states = [(check.get("conclusion") or check.get("status") or "").upper() for check in checks]
if not states:
    ci = "no checks"
elif all(state == "SUCCESS" for state in states):
    ci = "pass"
elif any(state == "FAILURE" for state in states):
    ci = "fail"
elif any(state in {"PENDING", "IN_PROGRESS", "QUEUED"} for state in states):
    ci = "run"
else:
    ci = "unknown"

review = match.get("reviewDecision") or ""
if review == "APPROVED":
    review_label = "approved"
elif review == "CHANGES_REQUESTED":
    review_label = "changes"
elif review == "REVIEW_REQUIRED":
    review_label = "review"
else:
    review_label = "no review"

draft = " draft" if match.get("isDraft") else ""
print(f"#{match.get('number')} {ci} {review_label}{draft}")
PY
}
```

Then insert this call before `load_worktrees`:

```bash
load_pr_json
```

Update the needs-action loop in `overview-status.sh` so failed PR checks come before dirty worktrees:

```bash
    if [[ "$pr_state" == *" fail"* ]]; then
        needs_action+=("$name|CI failed|gh pr checks $name")
        next="fix CI"
    elif [[ "$git_state" == dirty:* || "$git_state" == *" dirty:"* ]]; then
        dirty_count="${git_state#dirty:}"
        dirty_count="${dirty_count%% *}"
        needs_action+=("$name|$(plural "$dirty_count" "dirty file" "dirty files")|git status -sb")
        next="review changes"
    elif [[ "$pr_state" == "no PR" && "$name" != "main" && "$name" != "master" ]]; then
        next="push/open PR"
    fi
```

- [ ] **Step 4: Run tests**

Run:

```bash
bash tests/test-overview-status.sh
```

Expected:

```text
overview status tests passed
```

- [ ] **Step 5: Commit Task 2**

Run:

```bash
git add overview-status.sh tests/test-overview-status.sh
git commit -m "feat: summarize pr and ci in overview" -m "Add optional GitHub CLI integration to the compact Overview renderer without requiring gh for local-only repos." -m "- Load PR data once per refresh and map by worktree branch" -m "- Render compact PR, CI, review, and draft state" -m "- Promote failed checks into the needs-action lane"
```

## Task 3: Add Repo-Scoped AI and Resource Summary

**Files:**
- Modify: `overview-status.sh`
- Modify: `resource-monitor.sh`
- Modify: `tests/test-overview-status.sh`

- [ ] **Step 1: Add failing tests for AI env override and memory fallback**

Append this test block before the final `printf 'overview status tests passed\n'` line in `tests/test-overview-status.sh`:

```bash
ai_output="$(GROVE_OVERVIEW_NO_COLOR=1 GROVE_OVERVIEW_NO_GH=1 GROVE_OVERVIEW_NO_RESOURCE=1 GROVE_OVERVIEW_AGENT_MAP="feat/dirty=codex,main=claude" bash "$ROOT_DIR/overview-status.sh" "$repo")"
assert_contains "$ai_output" "feat/dirty" "ai branch row"
assert_contains "$ai_output" "codex" "codex agent state"
assert_contains "$ai_output" "main" "main branch row"
assert_contains "$ai_output" "claude" "claude agent state"
assert_contains "$ai_output" "agents 2 active" "active agent summary"

memory_output="$(GROVE_RESOURCE_TOTAL_MEM_BYTES=0 bash "$ROOT_DIR/resource-monitor.sh")"
assert_contains "$memory_output" "Memory: unknown" "resource monitor zero memory fallback"
assert_not_contains "$memory_output" "/ 0G" "resource monitor avoids zero total"
```

- [ ] **Step 2: Run test to verify failure**

Run:

```bash
bash tests/test-overview-status.sh
```

Expected:

```text
FAIL: codex agent state: expected to find 'codex'
```

The resource fallback assertion may also fail until `resource-monitor.sh` is updated.

- [ ] **Step 3: Add AI map override and process CWD matching**

In `overview-status.sh`, replace `ai_state_for_path()` with these functions:

```bash
AI_MATCH_COUNT=0

ai_state_from_override() {
    local branch="$1"
    local map="${GROVE_OVERVIEW_AGENT_MAP:-}"

    if [[ -z "$map" ]]; then
        return 1
    fi

    IFS=',' read -ra entries <<< "$map"
    for entry in "${entries[@]}"; do
        local key="${entry%%=*}"
        local value="${entry#*=}"
        if [[ "$key" == "$branch" ]]; then
            printf '%s' "$value"
            return 0
        fi
    done

    return 1
}

ai_state_for_path() {
    local path="$1" branch_name="$2"

    if [[ "${GROVE_OVERVIEW_NO_AI:-}" == "1" ]]; then
        printf 'idle'
        return
    fi

    local override
    if override="$(ai_state_from_override "$branch_name")"; then
        printf '%s' "$override"
        return
    fi

    local matches=()
    local editor active pid cwd

    for editor in claude gemini opencode codex; do
        active=$(pgrep -a -f "$editor" 2>/dev/null | grep -v grep | grep -v "overview-status" | grep -v "resource-monitor" || true)
        [[ -z "$active" ]] && continue
        while IFS= read -r proc; do
            [[ -z "$proc" ]] && continue
            pid=$(printf '%s\n' "$proc" | awk '{print $1}')
            cwd=$(lsof -p "$pid" -a -d cwd -Fn 2>/dev/null | grep '^n' | head -1 | sed 's/^n//' || true)
            if [[ "$cwd" == "$path" ]]; then
                matches+=("$editor")
            fi
        done <<< "$active"
    done

    if [[ "${#matches[@]}" -eq 0 ]]; then
        printf 'idle'
    elif [[ "${#matches[@]}" -eq 1 ]]; then
        printf '%s' "${matches[0]}"
    else
        printf 'multi'
    fi
}
```

Update the main row loop to pass the branch name:

```bash
    ai_state="$(ai_state_for_path "$path" "$name")"
    if [[ "$ai_state" != "idle" && "$ai_state" != "unknown" ]]; then
        AI_MATCH_COUNT=$((AI_MATCH_COUNT + 1))
    fi
```

Update the System line:

```bash
printf '  %s  agents %s active  stashes %s\n' "$(resource_state)" "$AI_MATCH_COUNT" "$(stash_count)"
```

- [ ] **Step 4: Add resource summary and memory fallback**

In `overview-status.sh`, replace `resource_state()` with:

```bash
resource_state() {
    if [[ "${GROVE_OVERVIEW_NO_RESOURCE:-}" == "1" ]]; then
        printf 'resources disabled'
        return
    fi

    local hot_cpu=0
    local hot_mem=0
    local proc_output=""
    local proc_name matches cpu_int mem_int

    for proc_name in claude gemini opencode codex lazygit; do
        matches=$(ps -eo pcpu,pmem,comm 2>/dev/null | grep -i "$proc_name" | grep -v grep || true)
        [[ -n "$matches" ]] && proc_output+="$matches"$'\n'
    done

    if [[ -n "$proc_output" ]]; then
        while IFS= read -r line; do
            [[ -z "$line" ]] && continue
            cpu_int=$(printf '%s\n' "$line" | awk '{print int($1)}')
            mem_int=$(printf '%s\n' "$line" | awk '{print int($2)}')
            [[ "${cpu_int:-0}" -ge 80 ]] && hot_cpu=1
            [[ "${mem_int:-0}" -ge 20 ]] && hot_mem=1
        done <<< "$proc_output"
    fi

    if [[ "$hot_cpu" -eq 1 && "$hot_mem" -eq 1 ]]; then
        printf 'hot cpu/memory'
    elif [[ "$hot_cpu" -eq 1 ]]; then
        printf 'hot cpu'
    elif [[ "$hot_mem" -eq 1 ]]; then
        printf 'hot memory'
    else
        printf 'resources normal'
    fi
}
```

In `resource-monitor.sh`, replace the total memory assignment block:

```bash
    total_mem_bytes=$(sysctl -n hw.memsize 2>/dev/null || echo 0)
    total_mem_gb=$(( total_mem_bytes / 1073741824 ))
```

with:

```bash
    total_mem_bytes="${GROVE_RESOURCE_TOTAL_MEM_BYTES:-}"
    if [[ -z "$total_mem_bytes" ]]; then
        total_mem_bytes=$(sysctl -n hw.memsize 2>/dev/null || echo 0)
    fi
    total_mem_gb=$(( total_mem_bytes / 1073741824 ))
```

Then wrap the memory percentage output in `resource-monitor.sh`:

```bash
    if (( total_mem_gb <= 0 )); then
        echo -e "  Memory: ${DIM}unknown${RESET}"
    else
        mem_pct=$(( (used_gb * 100) / total_mem_gb ))
        if (( mem_pct >= 85 )); then
            mem_color="$RED"
        elif (( mem_pct >= 65 )); then
            mem_color="$YELLOW"
        else
            mem_color="$GREEN"
        fi

        echo -e "  Memory: ${mem_color}${used_gb}G${RESET} / ${total_mem_gb}G (${mem_pct}%)"
    fi
```

Remove the old unconditional `mem_pct` calculation and `echo -e "  Memory: ..."` lines from `resource-monitor.sh`.

- [ ] **Step 5: Run tests**

Run:

```bash
bash tests/test-overview-status.sh
```

Expected:

```text
overview status tests passed
```

- [ ] **Step 6: Commit Task 3**

Run:

```bash
git add overview-status.sh resource-monitor.sh tests/test-overview-status.sh
git commit -m "feat: add repo-scoped agents and resource health" -m "Make Overview report AI agent activity for the current repo and avoid misleading resource percentages when system memory cannot be resolved." -m "- Match active agent processes to worktree directories" -m "- Add test override for deterministic agent-state coverage" -m "- Summarize resource health and guard zero-memory fallback"
```

## Task 4: Wire Compact Overview into Zellij Layout

**Files:**
- Modify: `layouts/workspace.kdl.template`
- Modify: `launch-worktrees.sh`
- Modify: `tests/test-launch-layout.sh`

- [ ] **Step 1: Add failing layout assertions**

In `tests/test-launch-layout.sh`, after the default layout `assert_not_contains "$default_layout" '🤖'` line, add:

```bash
assert_contains "$default_layout" "overview-status.sh" "default overview layout"
assert_contains "$default_layout" "Overview Details" "default overview layout"
assert_contains "$default_layout" "start_suspended=true" "default overview detail panes"
assert_contains "$default_layout" "worktree-status.sh" "default overview detail panes"
assert_contains "$default_layout" "ai-status.sh" "default overview detail panes"
assert_contains "$default_layout" "resource-monitor.sh" "default overview detail panes"
```

- [ ] **Step 2: Run layout test to verify failure**

Run:

```bash
bash tests/test-launch-layout.sh
```

Expected:

```text
FAIL: default overview layout: expected to find 'overview-status.sh'
```

- [ ] **Step 3: Update Overview layout template**

Replace the Overview tab block in `layouts/workspace.kdl.template` with:

```kdl
    // Overview tab - compact control tower with suspended detail panes
    tab name="Overview" color="cyan" cwd="{{GROVE_INSTALL_DIR}}" {
        pane split_direction="vertical" {
            pane command="bash" name="Overview Control Tower" size="70%" {
                args "-c" "while true; do _out=$(bash ./overview-status.sh \"{{REPO_PATH}}\" 2>/dev/null); clear; printf '%s' \"$_out\"; sleep 15; done"
            }

            pane name="Overview Details" size="30%" stacked=true {
                pane command="bash" name="Worktree Details" start_suspended=true {
                    args "-c" "while true; do _out=$(bash ./worktree-status.sh \"{{REPO_PATH}}\" 2>/dev/null); clear; printf '%s' \"$_out\"; sleep 30; done"
                }
                pane command="bash" name="AI Details" start_suspended=true {
                    args "-c" "while true; do _out=$(bash ./ai-status.sh 2>/dev/null); clear; printf '%s' \"$_out\"; sleep 60; done"
                }
                // {{GITHUB_STACK_PANES}}
                pane command="bash" name="Global Stash & WIP" start_suspended=true {
                    args "-c" "while true; do _out=$(bash ./stash-status.sh \"{{REPO_PATH}}\" 2>/dev/null); clear; printf '%s' \"$_out\"; sleep 30; done"
                }
                pane command="bash" name="Resources" start_suspended=true {
                    args "-c" "while true; do _out=$(bash ./resource-monitor.sh 2>/dev/null); clear; printf '%s' \"$_out\"; sleep 15; done"
                }
            }
        }
    }
```

- [ ] **Step 4: Update generated GitHub detail panes to start suspended**

In `launch-worktrees.sh`, inside `if $HAS_GH; then`, replace the PR/CI pane generation block with:

```bash
        {
            printf '                pane command="bash" name="PR Status" start_suspended=true {\n'
            printf '                    args "-c" "while true; do _out=$(bash ./pr-status.sh \\\"%s\\\" 2>/dev/null); clear; printf '\''%%s'\'' \\\"$_out\\\"; sleep 60; done"\n' "$esc_repo"
            printf '                }\n'
            printf '                pane command="bash" name="CI / GitHub Actions" start_suspended=true {\n'
            printf '                    args "-c" "while true; do _out=$(bash ./ci-status.sh \\\"%s\\\" 2>/dev/null); clear; printf '\''%%s'\'' \\\"$_out\\\"; sleep 60; done"\n' "$esc_repo"
            printf '                }\n'
        } >> "$gh_panes_file"
```

- [ ] **Step 5: Run layout test**

Run:

```bash
bash tests/test-launch-layout.sh
```

Expected:

```text
layout tests passed
```

- [ ] **Step 6: Generate layout manually**

Run:

```bash
bash ./launch-worktrees.sh --write-layout /tmp/grove-layout.kdl .
sed -n '1,140p' /tmp/grove-layout.kdl
```

Expected: output includes `Overview Control Tower`, `overview-status.sh`, `Overview Details`, and `start_suspended=true`.

- [ ] **Step 7: Commit Task 4**

Run:

```bash
git add layouts/workspace.kdl.template launch-worktrees.sh tests/test-launch-layout.sh
git commit -m "feat: make compact overview the primary zellij pane" -m "Wire Grove's Overview tab to the compact control tower while keeping verbose dashboards available as suspended detail panes." -m "- Replace default verbose Overview panes with overview-status.sh" -m "- Preserve existing worktree, AI, GitHub, stash, and resource dashboards in a detail stack" -m "- Update layout tests for compact Overview wiring"
```

## Task 5: Update Docs and Run Full Verification

**Files:**
- Modify: `README.md`
- Modify: `docs/architecture.md`

- [ ] **Step 1: Update README Overview text**

In `README.md`, replace the current Overview sentence:

```markdown
5. **Overview tab** — the first tab shows a live dashboard with worktree status, AI agent status, PR/CI status, and resource monitoring across all worktrees.
```

with:

```markdown
5. **Overview tab** — the first tab shows a compact control tower for worktrees, PR/CI, repo-scoped AI agents, stashes, and resource warnings. Verbose detail panes stay available in the Overview stack when you need deeper inspection.
```

- [ ] **Step 2: Update architecture Overview section**

In `docs/architecture.md`, replace the `## Overview Surfaces` section with:

```markdown
## Overview Surfaces

The Overview tab defaults to a compact control tower from `overview-status.sh`.

- Primary pane: `overview-status.sh`, showing Needs Action, Worktrees, and System sections.
- Detail stack: `worktree-status.sh`, `ai-status.sh`, optional GitHub panes, `stash-status.sh`, and `resource-monitor.sh`.
- GitHub detail panes are rendered only when `gh` is installed and authenticated.

Compact status is repo-scoped:

- `overview-status.sh`: branch dirty state, ahead/behind state, optional PR/CI summary, AI process state per worktree, stash count, and resource health.
- `worktree-status.sh`: detailed worktree branch/dirty state.
- `ai-status.sh`: detailed AI dashboard and Claude token analytics.
- `pr-status.sh`: detailed pull request / CI status per branch.
- `ci-status.sh`: detailed recent GitHub Actions runs for the repo.
- `stash-status.sh`: detailed global stash list and dirty-worktree tracker.
- `resource-monitor.sh`: detailed CPU and memory usage for AI agents and tooling.
- `vendor/zjstatus/zjstatus.wasm`: vendored custom Zellij bar plugin.
```

- [ ] **Step 3: Run full test suite**

Run:

```bash
bash tests/test-overview-status.sh
bash tests/test-launch-layout.sh
```

Expected:

```text
overview status tests passed
layout tests passed
```

- [ ] **Step 4: Run manual smoke checks**

Run:

```bash
GROVE_OVERVIEW_NO_COLOR=1 bash ./overview-status.sh .
GROVE_OVERVIEW_NO_COLOR=1 bash ./overview-status.sh --full .
bash ./resource-monitor.sh
bash ./launch-worktrees.sh --layout-only . >/tmp/grove-layout.kdl
```

Expected:

```text
overview-status.sh compact output shows Grove Overview, Needs Action, Worktrees, and System.
overview-status.sh --full output includes worktree paths.
resource-monitor.sh does not show "/ 0G" memory.
launch-worktrees.sh exits 0 and writes layout output.
```

- [ ] **Step 5: Review git diff**

Run:

```bash
git diff -- overview-status.sh resource-monitor.sh layouts/workspace.kdl.template launch-worktrees.sh tests/test-overview-status.sh tests/test-launch-layout.sh README.md docs/architecture.md
```

Expected: diff only includes compact Overview implementation, resource fallback, tests, layout wiring, and docs.

- [ ] **Step 6: Commit Task 5**

Run:

```bash
git add README.md docs/architecture.md
git commit -m "docs: describe compact overview dashboard" -m "Update Grove docs so users understand the Overview tab now starts with a compact control tower while retaining detailed panes for deeper inspection." -m "- Update README Overview copy" -m "- Document compact and detail Overview surfaces in architecture docs"
```

## Self-Review Checklist

- Spec coverage: Tasks implement compact default, needs-action lane, git state, optional GitHub state, repo-scoped AI state, resource fallback, layout wiring, docs, and tests.
- Placeholder scan: Plan contains no deferred implementation placeholders.
- Type consistency: Function names used across tasks are `load_worktrees`, `display_branch`, `git_state_for_path`, `load_pr_json`, `gh_state_for_branch`, `ai_state_for_path`, `resource_state`, and `stash_count`.
- Scope check: Plan stays inside compact Overview feature and does not add web UI, daemons, or external AI calls.

## Execution Notes

- Run tasks from `/Users/thisguymartin/personal-workspace/grove`.
- Keep commits free of co-author, signed-off-by, AI, Codex, or Anthropic trailers.
- If git commit fails because `.git/index.lock` is sandbox-protected, rerun only the same `git commit` command with approved escalation.
- If a test needs `gh`, use the fake `gh` binary from tests instead of real network calls.
