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
grove .                      # use the saved default AI agent
grove claude                 # use claude
grove codex                  # use codex

# Worktree management (worktrunk backend when `wt` is installed, else git)
grove new <branch>     # create new branch + worktree
grove add <branch>     # add worktree for existing branch
grove cd <branch>      # cd into a worktree by branch name
grove prune            # remove worktrees for merged branches
grove info [branch]    # show path, HEAD, ahead/behind, dirty status
```

Run shell tests with `bash tests/test-agent-config.sh`, `bash tests/test-agent-runtime.sh`, `bash tests/test-installer.sh`, `bash tests/test-session-name.sh`, `bash tests/test-launch-layout.sh`, `bash tests/test-worktrees-lib.sh`, `bash tests/test-worktree-backend.sh`, `bash tests/test-legacy-aliases.sh`, and `bash tests/test-status-table.sh`, or all of them with `for t in tests/*.sh; do bash "$t" || exit 1; done`.

## Architecture
Canonical architecture reference: `docs/architecture.md`

## Conventions

- All scripts are Bash; use POSIX-compatible patterns where possible
- Scripts use ANSI color codes for terminal output
- Parse worktrees only through `lib/worktrees.sh`; the git backend stores them at `../worktrees/<repo-name>/<branch>/`, or beside `main/` in a bare layout
- Shell aliases support both Bash (`BASH_SOURCE[0]`) and Zsh (`${(%):-%x}`) path resolution
- `ai-status.sh` embeds Python for JSONL parsing via heredoc
