# Overview Control Tower Design

## Goal

Make Grove's Overview tab useful at a glance by replacing the current always-verbose dashboard with a compact, repo-scoped control tower.

Success means a user can launch `grove .`, look at the first screen, and answer:

- Which worktrees need action?
- Which branches are clean, dirty, ahead, behind, or missing PRs?
- Which PRs or checks are blocked?
- Which AI agents are active in this repo?
- Is local resource usage abnormal?

## Current State

Grove's Overview tab currently renders multiple live panes:

- `worktree-status.sh` for branch, dirty state, paths, recent commits, and changed files.
- `ai-status.sh` for active agents, global Claude token usage, and recent global Claude sessions.
- `pr-status.sh` and `ci-status.sh` when `gh` is installed and authenticated.
- `stash-status.sh` for stashes and dirty worktrees.
- `resource-monitor.sh` for AI/dev process usage and system memory/load.

This creates useful data but too much default noise. The most visible pane shows paths and recent commits for every worktree, even when all branches are clean. The AI pane is global, not repo-scoped, so unrelated projects can dominate the view. The resource pane can also show misleading values in some environments, as seen with `6G / 0G (600%)`.

## Design

Add a compact Overview mode as the default. Keep the current detailed views available behind an explicit full/details mode.

The compact screen is structured as:

```text
Grove Overview: grove  2 worktrees  1 needs action  updated 14:42

Needs Action
  feat/auth       CI failed       next: gh pr checks feat/auth
  fix/login       5 dirty files   next: git status -sb

Worktrees
  BRANCH                  GIT              PR/CI              AI        NEXT
  main                    clean            no PR              idle      -
  feat/grove-cli-verbs    clean            no PR              idle      push/open PR

System
  resources normal        agents 0 active  stashes 0
```

### Information Priority

The top of the tab shows only actionable exceptions. Clean state is summarized, not repeated.

Priority order:

1. Failed CI or failing required PR checks.
2. Dirty worktrees.
3. Ahead or behind upstream.
4. Open PR review state.
5. Active AI agent per worktree.
6. Stashes.
7. Resource warnings.

This follows progressive disclosure: show essential status first, then let the user opt into detail. The design keeps Overview closer to a car dashboard: warning lights and key gauges first, engine bay detail only when needed.

### Modes

Compact mode is default:

```bash
bash ./overview-status.sh /path/to/repo
```

Full mode keeps deeper detail:

```bash
bash ./overview-status.sh --full /path/to/repo
```

The existing pane scripts remain useful as detail renderers, but the default Overview should not require all of them to be visible at once.

### Layout

The Overview tab should reduce pane count:

- Left/top: compact control tower from `overview-status.sh`.
- Right stack: optional detail panes, suspended or stacked so they do not compete with the compact summary.

Zellij supports command panes, stacked panes, `start_suspended`, and swap layouts. Grove can use those primitives instead of introducing a new UI framework.

## Components

### `overview-status.sh`

New repo-scoped summary renderer.

Responsibilities:

- Parse `git worktree list --porcelain`.
- Gather status per worktree.
- Render `Needs Action`, `Worktrees`, and `System` sections.
- Support `--full`.
- Avoid global project data unless explicitly requested.

### Existing Scripts

Keep these scripts as detail sources:

- `worktree-status.sh`: detailed git view.
- `ai-status.sh`: detailed AI/token view.
- `pr-status.sh`: detailed PR view.
- `ci-status.sh`: detailed GitHub Actions view.
- `stash-status.sh`: detailed stash/WIP view.
- `resource-monitor.sh`: detailed process/system view.

The compact renderer should not shell out to all detail scripts and parse their ANSI output. It should gather raw data directly through `git`, `gh`, `ps`, and small focused helpers.

## Data Flow

```text
git worktree list --porcelain
-> overview-status.sh worktree model
-> per-worktree git status/ahead/behind
-> optional gh PR/check lookup
-> repo-scoped AI process lookup
-> resource/stash summary
-> compact terminal table
-> Zellij Overview tab
```

## GitHub Handling

GitHub data is optional.

If `gh` is missing:

```text
PR/CI: gh missing
```

If `gh` is present but unauthenticated:

```text
PR/CI: gh auth needed
```

If no PR exists for a branch:

```text
no PR
```

Use compact per-branch lookups conservatively to avoid slow refreshes. Prefer one repo-level PR list lookup and map by `headRefName`. Use direct PR check lookup only for branches with open PRs.

## AI Agent Handling

Repo-scoped AI status should match active processes to current worktree paths through process CWD where possible.

Compact AI states:

- `idle`
- `claude`
- `codex`
- `gemini`
- `opencode`
- `multi`
- `unknown`

Global Claude token totals should not appear in compact mode. They can remain in `ai-status.sh` or a future explicit `--global` mode.

## Resource Handling

Resource summary should show only:

- `normal`
- `hot cpu`
- `hot memory`
- `unknown`

If total memory cannot be resolved, do not calculate percentage. Show:

```text
memory unknown
```

This prevents misleading output like `6G / 0G (600%)`.

## Error Handling

The compact Overview should degrade quietly:

- Non-git path: print one clear error and exit non-zero.
- Missing `gh`: show status badge, do not exit non-zero.
- Unauthenticated `gh`: show status badge, do not exit non-zero.
- Missing upstream: show `no upstream`, not an error.
- Missing AI process CWD: show `unknown`, not an error.
- Resource command unavailable: show `resources unknown`, not an error.

## Testing

Testing should focus on shell output and layout generation:

- Add shell tests for compact rows using temporary git repos/worktrees.
- Add tests for dirty, clean, ahead, behind, no upstream, and detached states.
- Add tests for `gh` missing/unauthenticated behavior by overriding `PATH` or command lookup.
- Add tests for resource fallback when memory total is zero or unavailable.
- Extend layout tests to confirm Overview uses `overview-status.sh` by default and preserves detail panes in stacked/suspended form.

## Sources

- Local repo: `layouts/workspace.kdl.template`, `worktree-status.sh`, `ai-status.sh`, `pr-status.sh`, `ci-status.sh`, `stash-status.sh`, `resource-monitor.sh`.
- Zellij Layouts: https://zellij.dev/documentation/layouts.html
- Zellij Creating a Layout: https://zellij.dev/documentation/creating-a-layout
- Zellij Swap Layouts: https://zellij.dev/documentation/swap-layouts.html
- GitHub CLI `gh pr checks`: https://cli.github.com/manual/gh_pr_checks
- Git worktree docs: https://git-scm.com/docs/git-worktree.html
- Progressive disclosure reference: https://www.ibm.com/docs/en/technical-content?topic=practices-progressive-disclosure

## Non-Goals

- Do not build a web dashboard.
- Do not replace Zellij.
- Do not remove existing detail scripts.
- Do not add persistent background daemons.
- Do not send repo, process, token, or customer data to third-party AI services.
