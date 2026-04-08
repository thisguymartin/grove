# Command Reference

Canonical command reference for Grove. Keep this file as the source of truth for CLI examples and worktree helpers.

## Grove

```bash
grove                        # Show help
grove .                      # Launch workspace (current dir, opencode)
grove claude                 # Current dir, Claude CLI
grove gemini                 # Current dir, Gemini CLI
grove opencode               # Current dir, OpenCode
grove codex                  # Current dir, Codex
grove /path/to/repo          # Specific repo dir, opencode
grove /path/to/repo claude   # Specific repo dir, Claude CLI
grove /path/to/repo gemini   # Specific repo dir, Gemini CLI
grove /path/to/repo codex    # Specific repo dir, Codex
```

## Shell Aliases

These commands come from `git-worktree-aliases.sh` or `git-worktree-aliases.fish`.

| Command | Description |
| :------ | :---------- |
| `wtab <branch>` | Create a new branch + worktree |
| `wta <branch>` | Add worktree for an existing branch |
| `wtls` | List all worktrees |
| `wtrm <path>` | Remove a worktree |
| `wtp [base]` | Prune merged/squash-merged/rebased worktrees |
| `wtco <branch>` | `cd` into a worktree by branch name |
| `wtcd <branch>` | Same as `wtco` |
| `wtinfo [branch]` | Show path, HEAD, ahead/behind, dirty status |
| `wtdiff [branch]` | Show diff vs base branch |
| `wtrn <old> <new>` | Rename a worktree branch |
| `wtlock <path>` | Lock a worktree |
| `wtunlock <path>` | Unlock a worktree |
| `wtui [path]` | Launch Zellij with one tab per worktree |
| `wtstatus [path]` | Show live worktree status dashboard |
| `zj-kill` | Kill all Zellij sessions |

## Standalone Toolkit

```bash
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

## Typical Workflow

```bash
# Create worktrees
wtab feature/auth
wta existing-branch

# Launch Grove
grove .

# Jump into a worktree
wtco feature/auth

# Inspect state
wtinfo feature/auth
wtdiff feature/auth

# Clean up
wtrm /path/to/worktree
wtp
```
