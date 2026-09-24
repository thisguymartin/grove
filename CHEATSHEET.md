# Grove Cheatsheet

## Daily Workflow

Full command reference: [`docs/commands.md`](docs/commands.md)

| Command | Description |
| :--- | :--- |
| **`grove`** | **Show help** |
| **`grove .`** | **Launch workspace** with your saved default agent |
| `grove claude` | Launch with Claude |
| `grove opencode` | Launch with OpenCode |
| `grove gemini` | Launch with Gemini CLI |
| `grove codex` | Launch with Codex |
| `grove /path/to/repo` | Launch workspace for a specific repo directory |
| `grove /path gemini` | Launch for a specific repo with a specific AI editor |
| `zj-kill` | Kill all Zellij sessions (clean slate) |
| `lg` | Open LazyGit manually |

---

## Zellij (Window Manager)
*The workspace is split into "Panes" and "Tabs".*

| Goal | Shortcut | Notes |
| :--- | :--- | :--- |
| **Move Focus** | `Alt + Arrow Keys` | Or `Alt + h/j/k/l` |
| **New Pane** | `Alt + n` | Splits current pane |
| **Close Pane** | `Ctrl + d` | Or type `exit` |
| **New Tab** | `Alt + t` | Like a new browser tab |
| **Switch Tab** | `Alt + Left/Right` | Cycle through worktree tabs |
| **Resize** | `Alt + [ ]` or `Alt + = -` | Increase/Decrease size |
| **Scroll Mode** | `Ctrl + s` | Then use arrows/PgUp/PgDn |
| **Detach** | `Ctrl + o` then `d` | Leaves session running in background |
| **Unlock/Lock**| `Ctrl + g` | **Important:** If shortcuts stop working, press this. |

---

## Git Worktrees
*Work on multiple branches at the same time, each in its own directory and Zellij tab.*
*Requires: `source ~/workspace/grove/git-worktree-aliases.sh` in your shell.*

Canonical reference: [`docs/commands.md`](docs/commands.md)

| Command | Description |
| :--- | :--- |
| `grove` | **Show help** |
| `grove .` | **Launch** workspace — colored tabs per worktree using the saved agent |
| `grove new <branch>` | **Create** new branch + worktree |
| `grove add <branch>` | **Add** worktree for existing branch |
| `grove ls` | **List** all worktrees |
| `grove rm <branch>` | **Remove** a worktree |
| `grove prune` | **Prune** merged / squash-merged / rebased worktrees |
| `grove cd <branch>` | **cd** into a worktree by branch name |
| `grove info [branch]` | **Info** — path, HEAD, ahead/behind, dirty status |
| `grove diff [branch]` | **Diff** between worktree branch and base branch |
| `grove rename <old> <new>` | **Rename** a worktree's branch |
| `grove lock <path>` / `grove unlock <path>` | **Lock** / **unlock** a worktree |
| `zj-kill` | **Kill** all Zellij sessions |

With worktrunk installed, `grove new`, `grove add`, and `grove rm` use `wt`; set `GROVE_WORKTREE_BACKEND=git` to force plain git. Bare layouts (`myproject/.git` plus `myproject/main/`) work from any directory in the project.

The old `wt*` aliases are archived: set `GROVE_LEGACY_ALIASES=1` before sourcing the aliases file to load them. The `wt` name now belongs to worktrunk.

Tab navigation once inside the session:

| Goal | Shortcut |
| :--- | :--- |
| Switch to next worktree tab | `Alt + Right` |
| Switch to previous worktree tab | `Alt + Left` |
| Jump to tab by number | `Alt + <1-9>` |

---

## LazyGit
*Launch with `lg` or via the LazyGit pane in each worktree tab.*

| Goal | Shortcut | Notes |
| :--- | :--- | :--- |
| **Navigate** | `Arrow Keys` | Move between Files, Local, Commits panels |
| **Stage File** | `Space` | Toggles staged/unstaged |
| **Stage All** | `a` | Stages all files |
| **Commit** | `c` | Opens commit message dialog |
| **Push** | `P` | (Shift + p) Pushes to remote |
| **Pull** | `p` | Pulls from remote |
| **Undo** | `Z` | Undoes the last commit (Soft reset) |
| **View Diff** | `Enter` | Zoom into the changes of a file |
| **Help** | `?` | Shows all commands |
