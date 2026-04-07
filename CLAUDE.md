# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Grove is an AI-native terminal workspace that orchestrates **git worktrees**, **Zellij** (terminal multiplexer), **LazyGit**, and AI agents (Claude, Gemini, OpenCode, Codex) into a unified multi-branch development environment. It's 100% Bash shell scripts with no build step.

## Key Commands

Canonical command reference: `docs/commands.md`

```bash
# Install dependencies
brew bundle --file=brewfile

# Run Grove (from any git repo with worktrees)
grove                        # defaults to opencode as AI editor
grove claude                 # use claude
grove codex                  # use codex

# Worktree management (shell aliases from git-worktree-aliases.sh)
wtab <branch>          # create new branch + worktree
wta <branch>           # add worktree for existing branch
wtco <branch>          # cd into a worktree by branch name (shortcut)
wtinfo [branch]        # show path, HEAD, ahead/behind, dirty status
```

There are no tests or linting configured — this is a shell-script-only project.

## Architecture
Canonical architecture reference: `docs/architecture.md`

## Conventions

- All scripts are Bash; use POSIX-compatible patterns where possible
- Scripts use ANSI color codes for terminal output
- Worktrees are stored at `../worktrees/<repo-name>/<branch>/` relative to the main clone
- Shell aliases support both Bash (`BASH_SOURCE[0]`) and Zsh (`${(%):-%x}`) path resolution
- `ai-status.sh` embeds Python for JSONL parsing via heredoc
