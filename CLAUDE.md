# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Grove is an AI-native terminal workspace that orchestrates **git worktrees**, **Zellij** (terminal multiplexer), **LazyGit**, and AI agents (Claude, Gemini, OpenCode) into a unified multi-branch development environment. It's 100% Bash shell scripts with no build step.

## Key Commands

```bash
# Install dependencies
brew bundle --file=brewfile

# Run Grove (from any git repo with worktrees)
grove                  # defaults to claude as AI editor
grove gemini           # use gemini CLI
grove opencode         # use opencode

# Worktree management (shell aliases from git-worktree-aliases.sh)
wtab <branch>          # create new branch + worktree
wta <branch>           # add worktree for existing branch
wtrm <path>            # force remove worktree
wtls                   # list worktrees
wtp [base-branch]      # prune merged worktrees

# Standalone script (can be aliased as gwt)
bash git-worktree.sh new <branch>
bash git-worktree.sh add <branch>
bash git-worktree.sh rm <branch>
bash git-worktree.sh ls
bash git-worktree.sh prune
bash git-worktree.sh tab [--layout-only]
```

There are no tests or linting configured — this is a shell-script-only project.

## Architecture

### Entry Flow
```
grove [ai-editor] → launch-grove.sh → launch-worktrees.sh
```

`launch-worktrees.sh` is the core orchestrator:
1. Discovers worktrees via `git worktree list --porcelain`
2. Dynamically generates a Zellij KDL layout (one tab per worktree + Overview tab)
3. Kills any existing session, launches new Zellij session

### Per-Worktree Tab Layout (3 panes)
- **LazyGit** (70% width) — git UI focused on that worktree
- **AI Agent** (30% width) — Claude/Gemini/OpenCode cwd'd to worktree
- **Workbench Shell** (bottom 30% height) — for tests, servers, etc.

### Overview Tab (Cyan)
- `worktree-status.sh` (left 60%) — live worktree status, refreshes every 15s
- `ai-status.sh` (right 40%) — active Claude sessions + token usage, refreshes every 30s

### Key Files
| File | Purpose |
|------|---------|
| `launch-grove.sh` | Thin entry point wrapper |
| `launch-worktrees.sh` | Core: dynamic Zellij layout generation (~304 lines) |
| `git-worktree.sh` | Standalone worktree lifecycle management (~423 lines) |
| `git-worktree-aliases.sh` | Shell aliases/functions sourced in ~/.zshrc |
| `ai-status.sh` | Claude session dashboard with Python analytics |
| `worktree-status.sh` | Live worktree status dashboard |
| `layouts/git-worktrees.kdl` | Static reference layout (dynamic layout is generated instead) |
| `install/install.sh` | Installation/uninstallation script |

### Environment Variables
| Variable | Default | Purpose |
|----------|---------|---------|
| `GWT_BASE_BRANCH` | `main` | Base branch for merge detection in `wtp` |
| `GWT_WORKTREE_DIR` | `../worktrees/<repo>` | Worktree storage directory |
| `AI_EDITOR` | `claude` | AI editor per tab (`claude`, `gemini`, `opencode`) |
| `GROVE_DIR` | `$HOME/.local/share/grove` | Installation directory |

## Conventions

- All scripts are Bash; use POSIX-compatible patterns where possible
- Scripts use ANSI color codes for terminal output
- Worktrees are stored at `../worktrees/<repo-name>/<branch>/` relative to the main clone
- Shell aliases support both Bash (`BASH_SOURCE[0]`) and Zsh (`${(%):-%x}`) path resolution
- `ai-status.sh` embeds Python for JSONL parsing via heredoc
