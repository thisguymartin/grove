# Grove Cheatsheet

## Daily Workflow
| Command | Description |
| :--- | :--- |
| **`grove`** | **Launch workspace** (AI + Git + Workbench per worktree, default: claude) |
| `grove opencode` | Launch with OpenCode instead of Claude |
| `grove gemini` | Launch with Gemini CLI instead of Claude |
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

| Command | Description |
| :--- | :--- |
| `grove` | **Launch** workspace — colored tabs per worktree (default: claude) |
| `wtab <branch>` | **Create** new branch + worktree |
| `wta <branch>` | **Add** worktree for existing branch |
| `wtls` | **List** all worktrees (`git worktree list`) |
| `wtrm <path>` | **Remove** a worktree (force) |
| `wtp [main]` | **Prune** merged / squash-merged / rebased worktrees |
| `wtui` | **Open** Zellij with one tab per worktree |
| `zj-kill` | **Kill** all Zellij sessions |

Tab navigation once inside the session:

| Goal | Shortcut |
| :--- | :--- |
| Switch to next worktree tab | `Alt + Right` |
| Switch to previous worktree tab | `Alt + Left` |
| Jump to tab by number | `Alt + <1-9>` |

---

## Git Worktree Toolkit (`gwt`)

| Command | Action |
| :--- | :--- |
| `gwt new feature/foo` | Create new branch + worktree |
| `gwt add existing-branch` | Add worktree for existing branch |
| `gwt rm feature/foo` | Remove a worktree |
| `gwt ls` | List all worktrees |
| `gwt prune` | Remove merged/stale worktrees |
| `gwt tab` | **Launch Zellij with one tab per worktree** |

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
