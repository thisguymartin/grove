# Grove Setup & Installation Guide

Walk the user through installing and running Grove. Adapt based on their current state (fresh install vs already cloned).

## Prerequisites Check

First check what's already installed:
- `git --version`
- `brew --version` (Homebrew required for dependencies)
- `zellij --version` (required - terminal multiplexer)
- `lazygit --version` (optional - git TUI)

## Installation Methods

### One-liner (recommended for new users)
```bash
bash <(curl -s https://raw.githubusercontent.com/thisguymartin/grove/main/install/install.sh)
```

### Manual installation
1. Clone: `git clone https://github.com/thisguymartin/grove.git ~/.local/share/grove`
2. Install deps: `brew bundle --file=~/.local/share/grove/brewfile`
3. Add to shell RC (`~/.zshrc` or `~/.bashrc`):
   ```bash
   source ~/.local/share/grove/git-worktree-aliases.sh
   ```
4. Reload shell: `source ~/.zshrc`

### Development (already cloned)
If the user has the repo cloned locally for development:
1. `brew bundle --file=brewfile`
2. Source aliases: `source ./git-worktree-aliases.sh`

## Running Grove

Navigate to any git repository, then:
```bash
grove              # launch with OpenCode (default AI editor)
grove gemini       # launch with Gemini CLI
grove opencode     # launch with OpenCode
grove codex        # launch with Codex
```

## Worktree Commands (after sourcing aliases)

| Command | Description |
|---------|-------------|
| `wtab <branch>` | Create new branch + worktree |
| `wta <branch>` | Add worktree for existing branch |
| `wtls` | List all worktrees |
| `wtrm <path>` | Remove a worktree |
| `wtp` | Prune merged worktrees |
| `wtstatus` | Live worktree status dashboard |

## Zellij Navigation

| Shortcut | Action |
|----------|--------|
| `Alt+Left/Right` | Switch between worktree tabs |
| `Alt+Arrow Keys` | Focus between panes |
| `Ctrl+o, d` | Detach session (keeps running) |
| `zellij attach git-worktrees` | Reattach to session |

## Uninstalling

```bash
bash ~/.local/share/grove/install/install.sh --uninstall
```

## Troubleshooting

If the user has issues:
- Ensure they're inside a git repo when running `grove`
- Check Zellij is installed: `zellij --version`
- If aliases aren't working, ensure `git-worktree-aliases.sh` is sourced in their shell RC
- If already in a Zellij session, Grove will warn — exit first or use a different terminal
