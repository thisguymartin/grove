# Grove

Grove is an AI-native terminal workspace for developers who work across multiple git branches simultaneously. Run one command from any repo and get a fully wired Zellij session with a custom Grove tab bar: one tab per worktree, each pre-loaded with LazyGit, your AI agent of choice, and a shell.

No config files to edit. No sessions to manage. Just `grove` and you're in.


<img width="1918" height="973" alt="Screenshot 2026-03-09 at 9 33 50 AM" src="https://github.com/user-attachments/assets/facfcd25-08e5-4f51-b68c-757514ef767b" />

<img width="1907" height="974" alt="Screenshot 2026-03-09 at 9 35 41 AM" src="https://github.com/user-attachments/assets/1cc77fa8-63bd-4e31-b0cc-585a7cce4258" />


## How It Works

Grove is a thin shell layer on top of tools you already use — git worktrees, Zellij, LazyGit, and your AI agent.

1. **Worktrees** — each branch lives in its own directory on disk, so you can have `main`, `feature/auth`, and `fix-login` all checked out at the same time with no stashing.

2. **`grove`** — resumes this repository's existing Zellij session, or creates one when it does not exist. Each worktree becomes a tab. Use `grove up --fresh` when you intentionally want to rebuild the session.

3. **Each tab** gets three side-by-side panes:
   - **Left (60%):** LazyGit scoped to that worktree's directory
   - **Middle (~12%):** A Workbench shell — run tests, servers, whatever
   - **Right (~28%):** Your AI agent (`claude`, `gemini`, `opencode`, or `codex`) in that worktree

4. **Custom tab bar** — Grove vendors `zjstatus` and replaces the stock Zellij tab/status bars with one colorful top bar. It shows mode, worktree tabs, the active AI editor, and the Zellij session name. If you prefer the native Zellij bars, launch with `GROVE_ZELLIJ_BAR=stock grove`.

5. **Overview tab** — the first tab is one quiet, live status pane. Set `GROVE_STATUS_BIN` to an executable development build for typed git, PR/check, and repo-scoped agent status; otherwise Grove uses the shell worktree summary.

6. **Session reuse** — running `grove` again attaches without restarting agents or shells. `grove up --fresh` is the explicit replacement path.

The workflow: create worktrees with `wtab`/`wta`, run `grove`, and navigate between branches with `Alt+Left/Right`. Clean up finished branches with `wtrm` or `wtp`.

Architecture details: [`docs/architecture.md`](docs/architecture.md)

## Install

### Recommended: One-liner

**bash / zsh:**

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/thisguymartin/grove/main/install/install.sh)
```

The interactive installer asks which single AI CLI to install and use by default. Choose Codex, OpenCode, Claude Code, Gemini CLI, or none.

**fish shell or other piped/non-interactive installs:**

```fish
curl -fsSL https://raw.githubusercontent.com/thisguymartin/grove/main/install/install.sh | bash -s -- --agent codex
```

Replace `codex` with `opencode`, `claude`, `gemini`, or `none`. Piped installs require `--agent` so Grove never silently chooses or installs an AI CLI. The installer clones Grove, installs core Homebrew dependencies, installs only the selected agent when missing, saves it as the default, and wires up shell aliases. Re-running performs the existing clean reinstall.

To install to a custom directory:

**bash / zsh:**
```bash
GROVE_DIR=~/my/path bash <(curl -fsSL https://raw.githubusercontent.com/thisguymartin/grove/main/install/install.sh)
```

**fish shell:**
```fish
GROVE_DIR=~/my/path curl -fsSL https://raw.githubusercontent.com/thisguymartin/grove/main/install/install.sh | bash -s -- --agent opencode
```

### Manual

**bash / zsh:**

```bash
# 1. Clone
git clone https://github.com/thisguymartin/grove.git ~/.local/share/grove

# 2. Install dependencies
brew bundle --file=~/.local/share/grove/brewfile

# 3. Install one AI CLI, or skip this step
brew install --cask codex

# 4. Save the default agent
mkdir -p ~/.config/grove
printf 'default_ai=codex\n' > ~/.config/grove/config

# 5. Add to ~/.zshrc (or ~/.bashrc)
echo 'source ~/.local/share/grove/git-worktree-aliases.sh' >> ~/.zshrc

# 6. Reload
source ~/.zshrc
```

**fish shell:**

```fish
# 1. Clone
git clone https://github.com/thisguymartin/grove.git ~/.local/share/grove

# 2. Install dependencies
brew bundle --file=~/.local/share/grove/brewfile

# 3. Install one AI CLI, or skip this step
brew install anomalyco/tap/opencode

# 4. Save the default agent
mkdir -p ~/.config/grove
printf 'default_ai=opencode\n' > ~/.config/grove/config

# 5. Add to ~/.config/fish/config.fish
echo 'source ~/.local/share/grove/git-worktree-aliases.fish' >> ~/.config/fish/config.fish

# 6. Reload
source ~/.config/fish/config.fish
```

Agent install commands used by Grove:

| Selection | Install command |
| :--- | :--- |
| Codex | `brew install --cask codex` |
| OpenCode | `brew install anomalyco/tap/opencode` |
| Claude Code | `brew install --cask claude-code` |
| Gemini CLI | `npm install -g @google/gemini-cli` (the installer adds Node with Homebrew only when `npm` is missing) |
| None | No AI package is installed; save `default_ai=none` |

## Usage

`cd` into any git repo and run:

```bash
grove
```

Full command reference: [`docs/commands.md`](docs/commands.md)

To test the rendered Zellij layout locally without launching Grove directly:

```bash
bash ./launch-worktrees.sh --write-layout /tmp/grove-layout.kdl .
zellij --layout /tmp/grove-layout.kdl
```

To test the old stock Zellij bars:

```bash
GROVE_ZELLIJ_BAR=stock bash ./launch-worktrees.sh --write-layout /tmp/grove-layout.kdl .
zellij --layout /tmp/grove-layout.kdl
```

This will:

1. Discover all git worktrees in your current repo
2. Attach to the existing repository session when one is running
3. Otherwise launch Zellij with an **Overview tab** (first) + **one custom-bar tab per worktree**

On first launch, Zellij may ask for permission to load the vendored `zjstatus` plugin from `vendor/zjstatus/zjstatus.wasm`.

Detach from Zellij when you want agents and shells to keep running, then use `grove` to return.

## Commands

Core commands live in [`docs/commands.md`](docs/commands.md).

Most-used commands:

| Command | Description |
| :------ | :---------- |
| `grove` / `grove up` | Attach to or launch the repository workspace |
| `grove up --fresh` | Replace the repository workspace |
| `grove go <branch>` | Focus that branch tab, then attach |
| `grove status [path]` | Show the repository status once |
| `grove claude .` | Launch workspace with Claude |
| `grove codex .` | Launch workspace with Codex |
| `wtab <branch>` | Create a new branch + worktree |
| `wta <branch>` | Add worktree for an existing branch |
| `wtco <branch>` | Jump into a worktree directory |
| `wtinfo [branch]` | Show worktree status and upstream info |
| `wtp [base]` | Prune merged worktrees |

## Worktree Lifecycle

```bash
# Create worktrees
wtab feature/auth          # new branch + worktree
wta existing-branch        # worktree for existing remote branch

# List what you have
wtls

# Launch workspace with all worktrees as tabs
grove
grove claude .

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
```

## Session Management

`grove` reuses its repository session so running agents and shells survive terminal detach/reattach. Use `grove up --fresh` to kill and rebuild that session.

Grove keeps Zellij session names within Zellij's 24-character limit. Long repository names use a shortened readable prefix plus a stable checksum.

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

The installer manages one default agent at a time. Additional CLIs can be installed later and launched explicitly, such as `grove claude .`.

Grove vendors [`zjstatus`](https://github.com/dj95/zjstatus) for the custom Zellij bar. No separate install is required.

## Claude Code Integration

Grove includes a built-in [Claude Code](https://claude.ai/code) slash command for guided setup. After cloning the repo, run `/setup` in any Claude Code session to get interactive help with installation, configuration, and troubleshooting.

Project-level context is also provided via `CLAUDE.md` so Claude Code understands the architecture out of the box.

## Keybindings

See [CHEATSHEET.md](CHEATSHEET.md) for the full keyboard reference.

## License

MIT
