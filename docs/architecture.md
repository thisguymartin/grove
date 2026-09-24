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
2. Reads the worktree inventory from `lib/worktrees.sh` and resolves the repository root, so every worktree and a bare layout's project directory share one session.
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

The tab names are plain branch names or short commit SHAs for detached worktrees. The main worktree is always the first tab. The custom bar handles color and mode state and shows `ai:<editor> · <backend>` on the right.

## Worktree Inventory

`lib/worktrees.sh` is the only parser of `git worktree list --porcelain`. It prints one row per worktree:

```text
path<TAB>branch<TAB>head<TAB>flags
```

`branch` is the short name, or empty when detached. `head` is the full SHA. `flags` is a comma-joined subset of `main,locked`. The main row prints first, and a bare repository never becomes a row. In a normal clone the main worktree is the original clone. In a bare layout it is the worktree on the default branch (`origin/HEAD`, then `main`, then `master`), else the first worktree. Because `read` merges adjacent tabs, shell loops read `grove_worktree_fields`, which uses `\037` separators.

The same library resolves the repository root, its name, and where the git backend puts a new worktree.

## Worktree Backends

`lib/backend.sh` resolves `worktrunk` or `git` from `GROVE_WORKTREE_BACKEND`, else from whether `wt` is on `PATH`. In `git-worktree.sh`, `new`, `add`, and `rm` each have one `case` on the backend. worktrunk runs with `-C <main worktree>`. After creation Grove reads the new path from the inventory instead of parsing `wt` output. All other verbs are git-based for both backends.

## Overview Surface

The default Overview is one pane refreshed every 30 seconds. It runs the executable in `GROVE_STATUS_BIN` when configured, otherwise it falls back to `worktree-status.sh`.

`worktree-status.sh` prints one table that fits 80 columns: a `repo · backend · count · time` header, then one row per worktree. Dirty, behind, and detached rows sort first with a `!` marker, then the main worktree (`*`), then the rest by branch. Dirty rows list up to five changed files unless `--no-files` is passed, which is what `grove ls` does. Color is added only on a terminal without `NO_COLOR`.

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
- `legacy/wt-aliases.{sh,fish}`: archived `wt*` functions, loaded only with `GROVE_LEGACY_ALIASES=1`
- `ai-status.sh`: AI dashboard
- `worktree-status.sh`: worktree dashboard
- `pr-status.sh`: PR/CI dashboard
- `ci-status.sh`: GitHub Actions dashboard
- `stash-status.sh`: stash/WIP dashboard
- `resource-monitor.sh`: process/resource dashboard
- `install/install.sh`: installer/uninstaller
- `lib/ai-agent.sh`: validated default-agent config and runtime resolution
- `lib/session.sh`: bounded, deterministic Zellij session naming
- `lib/worktrees.sh`: the worktree inventory and repository paths
- `lib/backend.sh`: worktrunk or git backend resolution
- `layouts/workspace.kdl.template`: internal Zellij template rendered by `launch-worktrees.sh`
- `vendor/zjstatus/`: pinned vendored `zjstatus` WASM, license, and version metadata

## Environment Variables

| Variable | Default | Purpose |
| :------- | :------ | :------ |
| `GWT_BASE_BRANCH` | `main` | Base branch for prune/diff behavior |
| `GWT_WORKTREE_DIR` | `../worktrees/<repo>` | Parent directory for worktrees the git backend creates in a normal clone |
| `GROVE_WORKTREE_BACKEND` | `worktrunk` if `wt` is installed, else `git` | Backend for `new`, `add`, and `rm` |
| `GROVE_LEGACY_ALIASES` | unset | `1` loads the archived `wt*` shell functions |
| `AI_EDITOR` | saved config | Per-process override for the default AI agent |
| `GROVE_ZELLIJ_BAR` | `zjstatus` | Zellij bar mode: `zjstatus` or `stock` |
| `GROVE_DIR` | `$HOME/.local/share/grove` | Install location |
| `GROVE_STATUS_BIN` | unset | Executable experimental Go status renderer |

The installer writes `default_ai=<codex|opencode|claude|gemini|none>` to `${XDG_CONFIG_HOME:-$HOME/.config}/grove/config`. The parser reads only the validated value and never sources the file as shell code. Manual checkouts without this file retain the old OpenCode default.

## Conventions

- Bash-first implementation, no build step
- Terminal-first workflow centered on Zellij + git worktrees
- The git backend stores worktrees under `../worktrees/<repo-name>/<branch>/`, or beside `main/` in a bare layout
- Shell aliases support bash/zsh and fish
- `ai-status.sh` uses embedded Python for Claude JSONL parsing

## Current Cleanup Direction

The project is being reorganized to reduce duplicated docs and make command behavior easier to maintain.

- `docs/commands.md` is the canonical command reference
- `README.md` should stay focused on install + quick start
- Architecture and implementation detail should live here rather than in the README
