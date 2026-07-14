# Architecture

Grove is a bash-first terminal workspace that wires together git worktrees, Zellij, LazyGit, AI CLIs, and a vendored `zjstatus` bar into a single multi-branch development environment.

## Entry Flow

```text
grove [up] [--fresh] [ai-editor] [path]
-> launch-grove.sh
-> lib/ai-agent.sh resolves the agent
-> attach existing repo session
-> or launch-worktrees.sh --ai <editor> [path]
```

## Runtime Model

`launch-worktrees.sh` is the core orchestrator.

1. Resolves the target repo and AI editor using explicit argument -> `AI_EDITOR` -> saved config -> legacy OpenCode fallback.
2. Discovers worktrees via `git worktree list --porcelain`.
3. Chooses the Zellij bar mode from `GROVE_ZELLIJ_BAR`.
4. Generates a Zellij layout dynamically.
5. Builds a deterministic session name capped at Zellij's 24-character limit.
6. Attaches when that repository session already exists.
7. Creates a new session only when missing; `--fresh` explicitly replaces it.

The default bar mode is `zjstatus`. If `vendor/zjstatus/zjstatus.wasm` is missing, Grove falls back to stock Zellij bars and prints a warning. `GROVE_ZELLIJ_BAR=stock` forces the native `zellij:tab-bar` and `zellij:status-bar`.

## Per-Worktree Layout

Each worktree becomes its own Zellij tab.

- Left: LazyGit scoped to that worktree
- Top-right: AI agent (`claude`, `gemini`, `opencode`, or `codex`)
- Bottom-right: Workbench shell for tests, servers, and ad hoc commands

The tab names are plain branch names or short commit SHAs for detached worktrees. The custom bar handles color and mode state, so Grove no longer prefixes tab names with emoji.

## Overview Surface

The default Overview is one pane refreshed every 30 seconds. It runs the executable in `GROVE_STATUS_BIN` when configured, otherwise it falls back to `worktree-status.sh`.

The experimental Go flow is:

```text
git + gh + Zellij pane JSON -> app.Service -> Workspace snapshot
                                  -> compact text | full text | JSON
```

Git failures are fatal. Missing or failing optional GitHub/Zellij integrations are recorded as `unknown`; they never produce guessed PR actions. The older token, PR, CI, stash, and resource scripts remain callable as diagnostics but do not start by default.

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
- `lib/ai-agent.sh`: validated default-agent config and runtime resolution
- `lib/session.sh`: bounded, deterministic Zellij session naming
- `layouts/workspace.kdl.template`: internal Zellij template rendered by `launch-worktrees.sh`
- `vendor/zjstatus/`: pinned vendored `zjstatus` WASM, license, and version metadata

## Environment Variables

| Variable | Default | Purpose |
| :------- | :------ | :------ |
| `GWT_BASE_BRANCH` | `main` | Base branch for prune/diff behavior |
| `GWT_WORKTREE_DIR` | `../worktrees/<repo>` | Parent directory for created worktrees |
| `AI_EDITOR` | saved config | Per-process override for the default AI agent |
| `GROVE_ZELLIJ_BAR` | `zjstatus` | Zellij bar mode: `zjstatus` or `stock` |
| `GROVE_DIR` | `$HOME/.local/share/grove` | Install location |
| `GROVE_STATUS_BIN` | unset | Executable experimental Go status renderer |

The installer writes `default_ai=<codex|opencode|claude|gemini|none>` to `${XDG_CONFIG_HOME:-$HOME/.config}/grove/config`. The parser reads only the validated value and never sources the file as shell code. Manual checkouts without this file retain the old OpenCode default.

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
