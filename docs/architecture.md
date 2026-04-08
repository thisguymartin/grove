# Architecture

Grove is a bash-first terminal workspace that wires together git worktrees, Zellij, LazyGit, and AI CLIs into a single multi-branch development environment.

## Entry Flow

```text
grove [path] [ai-editor]
-> launch-grove.sh [path] [ai-editor]
-> launch-worktrees.sh --ai <editor> [path]
```

## Runtime Model

`launch-worktrees.sh` is the core orchestrator.

1. Resolves the target repo and AI editor.
2. Discovers worktrees via `git worktree list --porcelain`.
3. Generates a Zellij layout dynamically.
4. Replaces any existing Grove session for that repo.
5. Launches a new Zellij session.

## Per-Worktree Layout

Each worktree becomes its own Zellij tab.

- Left: LazyGit scoped to that worktree
- Top-right: AI agent (`claude`, `gemini`, `opencode`, or `codex`)
- Bottom-right: Workbench shell for tests, servers, and ad hoc commands

## Overview Surfaces

The dashboard scripts provide live visibility across all active worktrees.

- Left (core): `worktree-status.sh`, `ai-status.sh`
- Right (stacked): `pr-status.sh`, `ci-status.sh`, `stash-status.sh`, `resource-monitor.sh`
- GitHub panes are rendered only when `gh` is installed and authenticated.

- `worktree-status.sh`: worktree branch/dirty state
- `ai-status.sh`: running AI agents and Claude token analytics
- `pr-status.sh`: pull request / CI status per branch
- `ci-status.sh`: recent GitHub Actions runs for the repo
- `stash-status.sh`: global stash list and dirty-worktree tracker
- `resource-monitor.sh`: CPU and memory usage for AI agents and tooling

## Repository Layout

Current top-level runtime files:

- `launch-grove.sh`: user-facing launcher
- `launch-worktrees.sh`: session/layout orchestrator
- `git-worktree.sh`: standalone worktree toolkit
- `git-worktree-aliases.sh`: bash/zsh aliases and functions
- `git-worktree-aliases.fish`: fish aliases and functions
- `ai-status.sh`: AI dashboard
- `worktree-status.sh`: worktree dashboard
- `pr-status.sh`: PR/CI dashboard
- `ci-status.sh`: GitHub Actions dashboard
- `stash-status.sh`: stash/WIP dashboard
- `resource-monitor.sh`: process/resource dashboard
- `install/install.sh`: installer/uninstaller
- `layouts/workspace.kdl.template`: internal Zellij template rendered by `launch-worktrees.sh`

## Environment Variables

| Variable | Default | Purpose |
| :------- | :------ | :------ |
| `GWT_BASE_BRANCH` | `main` | Base branch for prune/diff behavior |
| `GWT_WORKTREE_DIR` | `../worktrees/<repo>` | Parent directory for created worktrees |
| `AI_EDITOR` | `opencode` | Default AI editor per worktree tab |
| `GROVE_DIR` | `$HOME/.local/share/grove` | Install location |

## Conventions

- Bash-first implementation, no build step
- Terminal-first workflow centered on Zellij + git worktrees
- Worktrees stored under `../worktrees/<repo-name>/<branch>/`
- Shell aliases support bash/zsh and fish
- `ai-status.sh` uses embedded Python for Claude JSONL parsing

## Current Cleanup Direction

The project is being reorganized to reduce duplicated docs and make command behavior easier to maintain.

- `docs/commands.md` is the canonical command reference
- `README.md` should stay focused on install + quick start
- Architecture and implementation detail should live here rather than in the README
