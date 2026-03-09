# Grove

Grove is an AI-native terminal workspace for developers who work across multiple git branches simultaneously. Run one command from any repo and get a fully wired Zellij session — one color-coded tab per worktree, each pre-loaded with LazyGit, your AI agent of choice, and a shell.

No config files to edit. No sessions to manage. Just `grove` and you're in.

<img width="1918" height="973" alt="Screenshot 2026-03-09 at 9 33 50 AM" src="https://github.com/user-attachments/assets/facfcd25-08e5-4f51-b68c-757514ef767b" />


## How It Works

Grove is a thin shell layer on top of tools you already use — git worktrees, Zellij, LazyGit, and your AI agent.

1. **Worktrees** — each branch lives in its own directory on disk, so you can have `main`, `feature/auth`, and `fix-login` all checked out at the same time with no stashing.

2. **`grove .`** — discovers all worktrees in the current repo and generates a Zellij layout on the fly. Each worktree becomes a tab.

3. **Each tab** gets three side-by-side panes:
   - **Left (60%):** LazyGit scoped to that worktree's directory
   - **Middle (~12%):** A Workbench shell — run tests, servers, whatever
   - **Right (~28%):** Your AI agent (`claude`, `gemini`, or `opencode`) in that worktree

4. **Overview tab** — the first tab shows a live dashboard with worktree status, AI agent status, PR/CI status, and resource monitoring across all worktrees.

5. **Session hygiene** — `grove` auto-kills any previous session with the same name before launching, and sessions quit when you close the terminal. No stale Zellij sessions accumulating.

The workflow: create worktrees with `wtab`/`wta`, run `grove`, and navigate between branches with `Alt+Left/Right`. Clean up finished branches with `wtrm` or `wtp`.

## Install

### Recommended: One-liner

```bash
bash <(curl -s https://raw.githubusercontent.com/thisguymartin/grove/main/install/install.sh)
```

This will clone the repo, install brew dependencies, and wire up your shell aliases automatically. It detects your shell (zsh/bash) and is safe to run multiple times — re-running always does a clean reinstall (force-deletes the existing install, kills Grove Zellij sessions, and re-clones).

To install to a custom directory:

```bash
GROVE_DIR=~/my/path bash <(curl -s https://raw.githubusercontent.com/thisguymartin/grove/main/install/install.sh)
```

### Manual

```bash
# 1. Clone
git clone https://github.com/thisguymartin/grove.git ~/.local/share/grove

# 2. Install dependencies
brew bundle --file=~/.local/share/grove/brewfile

# 3. Add to ~/.zshrc (or ~/.bashrc)
echo 'source ~/.local/share/grove/git-worktree-aliases.sh' >> ~/.zshrc

# 4. Reload
source ~/.zshrc
```

## Usage

`cd` into any git repo and run:

```bash
grove                        # Show help
grove .                      # Launch workspace (current dir, claude)
grove gemini                 # Current dir, Gemini CLI
grove opencode               # Current dir, OpenCode
grove /path/to/repo          # Specific repo dir, claude
grove /path/to/repo gemini   # Specific repo dir, gemini
```

This will:

1. Discover all git worktrees in your current repo
2. Auto-kill any previous session with the same name
3. Launch Zellij with an **Overview tab** (first) + **one color-coded tab per worktree**

Sessions auto-quit when you close the terminal — no stale sessions.

## Commands

| Command               | Description                                                    |
| :-------------------- | :------------------------------------------------------------- |
| **`grove`**           | Show help                                                      |
| **`grove .`**         | Launch workspace — colored tabs per worktree (default: claude) |
| `grove opencode`      | Launch with OpenCode instead of Claude                         |
| `grove gemini`        | Launch with Gemini CLI instead of Claude                       |
| `grove /path`         | Launch workspace for a specific repo directory                 |
| `grove /path gemini`  | Launch for a specific repo with a specific AI editor           |
| **`wtab <branch>`**   | Create a new branch + worktree                                 |
| **`wta <branch>`**    | Add worktree for an existing remote branch                     |
| **`wtls`**            | List all worktrees                                             |
| **`wtrm <path>`**     | Remove a worktree (force)                                      |
| **`wtp [base]`**      | Prune worktrees merged/squash-merged/rebased into base branch  |
| **`wtcd <branch>`**   | `cd` into a worktree by branch name                            |
| **`wtinfo [branch]`** | Show path, HEAD, ahead/behind, dirty status for a worktree     |
| **`wtdiff [branch]`** | `git diff --stat` between worktree branch and base branch      |
| **`wtrn <old> <new>`**| Rename a worktree's branch                                     |
| **`wtlock <path>`**   | Lock a worktree                                                |
| **`wtunlock <path>`** | Unlock a worktree                                              |
| `wtui [path]`         | Launch Zellij per-worktree tabs (without AI editor arg)        |
| `wtstatus [path]`     | Live worktree status dashboard (standalone)                    |
| **`zj-kill`**         | Kill all Zellij sessions (clean slate)                         |

### Git Worktree Toolkit (`gwt`)

A standalone script for worktree lifecycle management:

```bash
alias gwt='~/.local/share/grove/git-worktree.sh'
```

| Command                       | Description                                  |
| :---------------------------- | :------------------------------------------- |
| `gwt new <branch>`            | Create a new branch and worktree             |
| `gwt add <branch>`            | Add a worktree for an existing branch        |
| `gwt rm <branch>`             | Remove a worktree (prompts to delete branch) |
| `gwt ls`                      | List all worktrees                           |
| `gwt prune`                   | Remove worktrees for merged/stale branches   |
| `gwt tab`                     | Launch Zellij with one tab per worktree      |
| `gwt cd <branch>`             | Print the worktree path for a branch         |
| `gwt info [branch]`           | Show path, HEAD, ahead/behind, dirty status  |
| `gwt diff [branch]`           | Diff between branch and base branch          |
| `gwt rename <old> <new>`      | Rename a worktree's branch                   |
| `gwt lock <path>`             | Lock a worktree                              |
| `gwt unlock <path>`           | Unlock a worktree                            |

### Git Config Aliases (optional)

Add to your `~/.gitconfig` `[alias]` section:

```gitconfig
[alias]
    wta  = "!f() { branch=$1; cur_git_dir=$(git rev-parse --show-toplevel); proj_dir=$(dirname \"$cur_git_dir\"); repo_name=$(basename \"$cur_git_dir\"); target=\"$proj_dir\"/worktrees/\"$repo_name\"/\"$branch\"; if [ ! -d $target ]; then git worktree add \"$target\"; fi; exit 0; }; f"
    wtab = "!f() { branch=$1; cur_git_dir=$(git rev-parse --show-toplevel); proj_dir=$(dirname \"$cur_git_dir\"); repo_name=$(basename \"$cur_git_dir\"); target=\"$proj_dir\"/worktrees/\"$repo_name\"/\"$branch\"; if [ ! -d $target ]; then git worktree add \"$target\" -b \"$branch\"; fi; exit 0; }; f"
    wtp  = "!f(){ set -eu; default_branch=$(git symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null | sed 's@^origin/@@' || true); main_branch=${1:-${default_branch:-main}}; git fetch -p origin >/dev/null 2>&1 || true; git worktree prune; }; f"
    wtls = worktree list
    wtrm = worktree remove --force
```

## Worktree Lifecycle

```bash
# Create worktrees
wtab feature/auth          # new branch + worktree
wta existing-branch        # worktree for existing remote branch

# List what you have
wtls

# Launch workspace with all worktrees as tabs
grove .

# Navigate tabs
# Alt+Left/Right to switch between worktree tabs
# Alt+Arrow Keys to move between panes

# Inspect worktrees
wtcd feature/auth          # cd into a worktree
wtinfo feature/auth        # show path, HEAD, ahead/behind, status
wtdiff feature/auth        # diff vs base branch

# Rename / lock
wtrn old-name new-name    # rename a worktree's branch
wtlock /path/to/worktree   # lock a worktree
wtunlock /path/to/worktree # unlock a worktree

# Clean up when done
wtrm /path/to/worktree    # remove a specific worktree
wtp                        # auto-prune merged worktrees

# Or via gwt (prompts to delete branch too)
gwt rm feature/auth
```

## Session Management

`grove` auto-kills its previous session before re-launching. Sessions also auto-quit when the terminal closes (`on_force_close "quit"`).

```bash
zj-kill                    # Kill ALL Zellij sessions (nuclear option)
zellij kill-session <name> # Kill a specific session
```

## Tab Colors

Each worktree tab cycles through **4 colors** (green, blue, yellow, orange). The Overview tab is always **cyan** (reserved, not in the cycling palette). Colors repeat if you have more than 4 worktrees. The main branch tab is auto-focused on launch.

## Worktree Directory Structure

Worktrees are created under a sibling `worktrees/` directory:

```
~/projects/
  my-repo/              <- your main clone
  worktrees/
    my-repo/
      feature/login/    <- worktree for feature/login branch
      bugfix/header/    <- worktree for bugfix/header branch
```

## Environment Variables

| Variable           | Default               | Description                                                              |
| :----------------- | :-------------------- | :----------------------------------------------------------------------- |
| `GWT_BASE_BRANCH`  | `main`                | Base branch used by `prune` to detect merged branches                    |
| `GWT_WORKTREE_DIR` | `../worktrees/<repo>` | Override the directory where worktrees are created                       |
| `AI_EDITOR`        | `claude`              | AI editor launched in each worktree tab (`claude`, `gemini`, `opencode`) |

## Requirements

- [Zellij](https://zellij.dev) — terminal multiplexer
- [LazyGit](https://github.com/jesseduffield/lazygit) — git TUI (optional, falls back to shell)
- [Claude Code](https://claude.ai/claude-code), [Gemini CLI](https://github.com/google-gemini/gemini-cli), or [OpenCode](https://github.com/opencode-ai/opencode) — AI agent (optional)

## Claude Code Integration

Grove includes a built-in [Claude Code](https://claude.ai/code) slash command for guided setup. After cloning the repo, run `/setup` in any Claude Code session to get interactive help with installation, configuration, and troubleshooting.

Project-level context is also provided via `CLAUDE.md` so Claude Code understands the architecture out of the box.

## Keybindings

See [CHEATSHEET.md](CHEATSHEET.md) for the full keyboard reference.

## License

MIT
