# Grove

Grove is an AI-native terminal workspace for developers who work across multiple git branches simultaneously. Run one command from any repo and get a fully wired Zellij session — one color-coded tab per worktree, each pre-loaded with LazyGit, your AI agent of choice, and a shell.

No config files to edit. No sessions to manage. Just `grove` and you're in.


<img width="1918" height="973" alt="Screenshot 2026-03-09 at 9 33 50 AM" src="https://github.com/user-attachments/assets/facfcd25-08e5-4f51-b68c-757514ef767b" />

<img width="1907" height="974" alt="Screenshot 2026-03-09 at 9 35 41 AM" src="https://github.com/user-attachments/assets/1cc77fa8-63bd-4e31-b0cc-585a7cce4258" />


## How It Works

Grove is a thin shell layer on top of tools you already use — git worktrees, Zellij, LazyGit, and your AI agent.

1. **Worktrees** — each branch lives in its own directory on disk, so you can have `main`, `feature/auth`, and `fix-login` all checked out at the same time with no stashing.

2. **`grove .`** — discovers all worktrees in the current repo and generates a Zellij layout on the fly. Each worktree becomes a tab.

3. **Each tab** gets three side-by-side panes:
   - **Left (60%):** LazyGit scoped to that worktree's directory
   - **Middle (~12%):** A Workbench shell — run tests, servers, whatever
   - **Right (~28%):** Your AI agent (`claude`, `gemini`, `opencode`, or `codex`) in that worktree

4. **Overview tab** — the first tab shows a live dashboard with worktree status, AI agent status, PR/CI status, and resource monitoring across all worktrees.

5. **Session hygiene** — `grove` auto-kills any previous session with the same name before launching, and sessions quit when you close the terminal. No stale Zellij sessions accumulating.

The workflow: create worktrees with `wtab`/`wta`, run `grove`, and navigate between branches with `Alt+Left/Right`. Clean up finished branches with `wtrm` or `wtp`.

Architecture details: [`docs/architecture.md`](docs/architecture.md)

## Install

### Recommended: One-liner

**bash / zsh:**

```bash
bash <(curl -s https://raw.githubusercontent.com/thisguymartin/grove/main/install/install.sh)
```

**fish shell** (process substitution works differently in fish — download and run directly):

```fish
curl -s https://raw.githubusercontent.com/thisguymartin/grove/main/install/install.sh | bash
```

This will clone the repo, install brew dependencies, and wire up your shell aliases automatically. It detects your shell (zsh/bash/fish) and is safe to run multiple times — re-running always does a clean reinstall (force-deletes the existing install, kills Grove Zellij sessions, and re-clones).

To install to a custom directory:

**bash / zsh:**
```bash
GROVE_DIR=~/my/path bash <(curl -s https://raw.githubusercontent.com/thisguymartin/grove/main/install/install.sh)
```

**fish shell:**
```fish
GROVE_DIR=~/my/path curl -s https://raw.githubusercontent.com/thisguymartin/grove/main/install/install.sh | bash
```

### Manual

**bash / zsh:**

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

**fish shell:**

```fish
# 1. Clone
git clone https://github.com/thisguymartin/grove.git ~/.local/share/grove

# 2. Install dependencies
brew bundle --file=~/.local/share/grove/brewfile

# 3. Add to ~/.config/fish/config.fish
echo 'source ~/.local/share/grove/git-worktree-aliases.fish' >> ~/.config/fish/config.fish

# 4. Reload
source ~/.config/fish/config.fish
```

## Usage

`cd` into any git repo and run:

```bash
grove .
```

Full command reference: [`docs/commands.md`](docs/commands.md)

To test the rendered Zellij layout locally without launching Grove directly:

```bash
bash ./launch-worktrees.sh --write-layout /tmp/grove-layout.kdl .
zellij --layout /tmp/grove-layout.kdl
```

This will:

1. Discover all git worktrees in your current repo
2. Auto-kill any previous session with the same name
3. Launch Zellij with an **Overview tab** (first) + **one color-coded tab per worktree**

Sessions auto-quit when you close the terminal — no stale sessions.

## Commands

Core commands live in [`docs/commands.md`](docs/commands.md).

Most-used commands:

| Command | Description |
| :------ | :---------- |
| `grove .` | Launch workspace with `opencode` as the default AI editor |
| `grove claude` | Launch workspace with Claude |
| `grove codex` | Launch workspace with Codex |
| `wtab <branch>` | Create a new branch + worktree |
| `wta <branch>` | Add worktree for an existing branch |
| `wtco <branch>` | Jump into a worktree directory |
| `wtinfo [branch]` | Show worktree status and upstream info |
| `wtp [base]` | Prune merged worktrees |

### Git Worktree Toolkit (`gwt`)

A standalone script for worktree lifecycle management. See [`docs/commands.md`](docs/commands.md) for the full command list.

```bash
alias gwt='~/.local/share/grove/git-worktree.sh'
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
wtco feature/auth          # cd into a worktree
wtcd feature/auth          # same as wtco
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

## Project Docs

- [`docs/commands.md`](docs/commands.md): canonical command reference
- [`docs/architecture.md`](docs/architecture.md): runtime flow, layout, and implementation structure
- [`CHEATSHEET.md`](CHEATSHEET.md): quick reference and keybindings

Note: `layouts/workspace.kdl.template` is an internal template rendered by Grove. It is not meant to be passed directly to `zellij --layout`.

## Requirements

- [Zellij](https://zellij.dev) — terminal multiplexer
- [LazyGit](https://github.com/jesseduffield/lazygit) — git TUI (optional, falls back to shell)
- [Claude Code](https://claude.ai/claude-code), [Gemini CLI](https://github.com/google-gemini/gemini-cli), [OpenCode](https://github.com/opencode-ai/opencode), or Codex CLI (`codex`) — AI agent (optional)

## Claude Code Integration

Grove includes a built-in [Claude Code](https://claude.ai/code) slash command for guided setup. After cloning the repo, run `/setup` in any Claude Code session to get interactive help with installation, configuration, and troubleshooting.

Project-level context is also provided via `CLAUDE.md` so Claude Code understands the architecture out of the box.

## Keybindings

See [CHEATSHEET.md](CHEATSHEET.md) for the full keyboard reference.

## License

MIT
