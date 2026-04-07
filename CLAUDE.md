# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Grove is an AI-native terminal workspace that orchestrates **git worktrees**, **Zellij** (terminal multiplexer), **LazyGit**, and AI agents (Claude, Gemini, OpenCode, Codex) into a unified multi-branch development environment. It's 100% Bash shell scripts with no build step.

## Key Commands

```bash
# Install dependencies
brew bundle --file=brewfile

# Run Grove (from any git repo with worktrees)
grove                        # defaults to opencode as AI editor
grove gemini                 # use gemini CLI
grove opencode               # use opencode
grove codex                  # use codex
grove /path/to/repo          # specific repo dir, claude
grove /path/to/repo gemini   # specific repo dir, gemini

# Worktree management (shell aliases from git-worktree-aliases.sh)
wtab <branch>          # create new branch + worktree
wta <branch>           # add worktree for existing branch
wtrm <path>            # force remove worktree
wtls                   # list worktrees
wtp [base-branch]      # prune merged worktrees
wtcd <branch>          # cd into a worktree by branch name
wtinfo [branch]        # show path, HEAD, ahead/behind, dirty status
wtdiff [branch]        # diff vs base branch
wtrn <old> <new>       # rename a worktree's branch
wtlock <path>          # lock a worktree
wtunlock <path>        # unlock a worktree

# Standalone script (can be aliased as gwt)
bash git-worktree.sh new <branch>
bash git-worktree.sh add <branch>
bash git-worktree.sh rm <branch>
bash git-worktree.sh ls
bash git-worktree.sh prune
bash git-worktree.sh tab [--layout-only]
bash git-worktree.sh cd <branch>
bash git-worktree.sh info [branch]
bash git-worktree.sh diff [branch]
bash git-worktree.sh rename <old> <new>
bash git-worktree.sh lock <path>
bash git-worktree.sh unlock <path>
```

There are no tests or linting configured — this is a shell-script-only project.

## Architecture

### Entry Flow
```
grove [path] [ai-editor] → launch-grove.sh [path] [ai-editor] → launch-worktrees.sh --ai <editor> [path]
```

`launch-worktrees.sh` is the core orchestrator:
1. Discovers worktrees via `git worktree list --porcelain`
2. Dynamically generates a Zellij KDL layout (one tab per worktree + Overview tab)
3. Kills any existing session, launches new Zellij session

### Per-Worktree Tab Layout (3 panes)
- **LazyGit** (30% width, left) — git UI focused on that worktree
- **Workbench Shell** (top-right, 70% height) — for tests, servers, etc.
- **AI Agent** (bottom-right, 30% height) — Claude/Gemini/OpenCode/Codex cwd'd to worktree

### Overview Tab (Cyan) — 4 panes
- `worktree-status.sh` (top-left 40%) — live worktree status, refreshes every 15s
- `ai-status.sh` (top-center 30%) — active AI agents + Claude token usage, refreshes every 30s
- `pr-status.sh` (top-right 30%) — PR/CI status per worktree branch, refreshes every 60s
- `resource-monitor.sh` (bottom 30%) — CPU/memory for AI agent processes, refreshes every 5s

### Key Files
| File | Purpose |
|------|---------|
| `launch-grove.sh` | Thin entry point wrapper |
| `launch-worktrees.sh` | Core: dynamic Zellij layout generation (~304 lines) |
| `git-worktree.sh` | Standalone worktree lifecycle management (~423 lines) |
| `git-worktree-aliases.sh` | Shell aliases/functions sourced in ~/.zshrc |
| `ai-status.sh` | AI agent dashboard (Claude/Gemini/OpenCode/Codex) with token analytics |
| `worktree-status.sh` | Live worktree status dashboard |
| `pr-status.sh` | PR/CI status dashboard per worktree branch (requires `gh`) |
| `resource-monitor.sh` | CPU/memory monitor for AI agent processes |
| `layouts/git-worktrees.kdl` | Static reference layout (dynamic layout is generated instead) |
| `install/install.sh` | Installation/uninstallation script |

### Environment Variables
| Variable | Default | Purpose |
|----------|---------|---------|
| `GWT_BASE_BRANCH` | `main` | Base branch for merge detection in `wtp` |
| `GWT_WORKTREE_DIR` | `../worktrees/<repo>` | Worktree storage directory |
| `AI_EDITOR` | `opencode` | AI editor per tab (`claude`, `gemini`, `opencode`, `codex`) |
| `GROVE_DIR` | `$HOME/.local/share/grove` | Installation directory |

## Conventions

- All scripts are Bash; use POSIX-compatible patterns where possible
- Scripts use ANSI color codes for terminal output
- Worktrees are stored at `../worktrees/<repo-name>/<branch>/` relative to the main clone
- Shell aliases support both Bash (`BASH_SOURCE[0]`) and Zsh (`${(%):-%x}`) path resolution
- `ai-status.sh` embeds Python for JSONL parsing via heredoc
