# Command Reference

Canonical command reference for Grove. Keep this file as the source of truth for CLI examples and worktree helpers.

Grove now uses a single, git-style entry point: **`grove <verb>`** — like `git add` / `git commit`. One mental model, all discoverable via `grove help`. The old `wt*` shell aliases are archived and opt-in (see [Legacy aliases](#legacy-aliases)).

## Workspace

```bash
grove                           # Attach to or launch this repo's Zellij workspace
grove up [--fresh] [ai-editor] [path]
                                # Same behavior; --fresh replaces the session
grove status [path] [--full | --json]
                                # One-shot status table; flags need GROVE_STATUS_BIN
grove agents                   # Live dashboard of running AI agents
```

`ai-editor` is one of `claude | gemini | opencode | codex`. Without an explicit value, Grove uses `AI_EDITOR`, then `default_ai` from `${XDG_CONFIG_HOME:-$HOME/.config}/grove/config`. Manual checkouts without a config retain the legacy `opencode` fallback.

## Worktrees

| Command | Description |
| :------ | :---------- |
| `grove new <branch>` | Create a new branch + worktree |
| `grove add <branch>` | Add a worktree for an existing branch |
| `grove ls` | List all worktrees (the status table without file lines) |
| `grove rm <branch>` | Remove a worktree (git backend prompts to delete the branch; worktrunk deletes it only when merged) |
| `grove cd <branch>` | Jump into a worktree (changes shell cwd) |
| `grove pick` | Pick a worktree interactively (fzf, falls back to a numbered menu), then cd into it |
| `grove main` | Jump into the main worktree (changes shell cwd) |
| `grove which <branch>` | Print a worktree's path |
| `grove root` | Print the main worktree path (never a bare repository) |
| `grove run <branch> [--] <cmd>` | Run a command inside a worktree's directory |
| `grove exec [--] <cmd>` | Run a command in EVERY worktree (fan-out) |
| `grove sync [branch]` | Fetch + rebase the branch onto its base (refuses a dirty tree) |
| `grove pr [branch]` | Open (or create) the branch's GitHub PR (needs `gh`) |
| `grove mv <branch> <new-path>` | Move a worktree to a new directory |
| `grove log [branch]` | `git log` of the branch vs base |
| `grove open <branch>` | Open a worktree in your editor (`$GROVE_EDITOR`) |
| `grove info [branch]` | Show path, HEAD, ahead/behind, dirty status |
| `grove diff [branch]` | `git diff --stat` between branch and base |
| `grove rename <old> <new>` | Rename a worktree's branch |
| `grove prune` | Remove worktrees for merged/stale branches |
| `grove lock <path>` / `grove unlock <path>` | Lock / unlock a worktree |

> `grove cd`, `grove pick`, and `grove main` change the **calling shell's** cwd, so they run
> inside the `grove()` shell function (sourced from `git-worktree-aliases.sh`). A subprocess
> can't `cd` for you — that's why these are special-cased. `grove pick` lists each worktree
> with the **branch name in color** followed by its **path**; running `grove pick` (the raw
> subcommand) just prints the chosen path.

`grove status` and `grove ls` print one table, attention first:

```text
myproject · worktrunk · 3 worktrees · 16:11
! feat/x  2 changed  ↑1 ↓3  9c1d2e0 wip: checkout flow
  main *  clean             7bad393 init
  feat/y  clean      ↑2     41ab77c add tests
```

`!` marks a dirty, behind, or detached worktree and `*` marks the main worktree. `grove status` also lists up to five changed files under each dirty row.

## Worktree backends

`grove new`, `grove add`, and `grove rm` run through a backend. Every other verb uses git directly.

| Backend | Selected when | new / add / rm |
| :------ | :------------ | :------------- |
| `worktrunk` | `wt` is on `PATH` | `wt switch --create`, `wt switch`, `wt remove` |
| `git` | `wt` is missing | `git worktree add` / `git worktree remove` |

Set `GROVE_WORKTREE_BACKEND=git` or `GROVE_WORKTREE_BACKEND=worktrunk` to choose one explicitly. With worktrunk, `wt` decides where the worktree goes and whether to delete a merged branch. With git, new worktrees go to `../worktrees/<repo>/<branch>` (or `GWT_WORKTREE_DIR`), and to `<project>/<branch>` in a bare layout with `/` replaced by `-`.

### Bare repository layout

Grove supports worktrunk's bare layout, where every branch, including `main`, is a sibling directory:

```text
myproject/
├── .git/        # bare repository
├── main/        # worktree for main
└── feat-x/      # worktree for feat/x
```

```bash
git clone --bare <url> myproject/.git
cd myproject && wt switch main    # creates myproject/main
```

Without configuration, worktrunk 0.79 places bare-layout worktrees at `myproject/.git.<branch>`. For sibling directories, add this to `~/.config/worktrunk/config.toml`:

```toml
worktree-path = "{{ repo_path }}/../{{ branch | sanitize }}"
```

Grove runs from any directory in the project, including the bare `myproject/` itself. The bare repository never becomes a tab or a status row, and `grove main` goes to `myproject/main`.

## AI & navigation

```bash
grove go <branch>              # Jump to the worktree's Zellij tab (or attach the session)
grove agent <branch> [ai]      # Open/focus an AI agent tab for a worktree
grove agents                   # Live dashboard of running AI agents
```

### Where is my agent at?

The headline AI-native flow — you kicked off an agent in a worktree and want to get back to it:

```bash
grove agents                   # see which agents are running + token usage
grove go feat/checkout         # jump straight to that agent's Zellij tab

# from a fresh terminal (outside Zellij):
grove go feat/checkout         # re-attaches the grove session; the agent kept running
```

Tabs are named **exactly by branch**, so `grove go <branch>` resolves directly via
`zellij action go-to-tab-name <branch>`. Detaching (`Ctrl+o d`) leaves agents running.

## Example scenarios

```bash
# 1. Spin up a feature
grove new feat/checkout                  # branch + worktree, auto-adds a Zellij tab
grove run feat/checkout -- npm run dev   # dev server, in that worktree's dir

# 2. Update a stale branch and ship it
grove sync feat/checkout                 # fetch + rebase onto origin/main (refuses if dirty)
grove pr feat/checkout                   # opens existing PR, or creates one via gh

# 3. Run something across every worktree
grove exec -- git fetch                  # fan-out to all worktrees
grove exec -- npm install
```

## Back-compat

These launch forms still work:

```bash
grove .                        # launch with the saved default agent
grove claude [path]            # launch with Claude
zj-kill                        # kill all Zellij sessions
```

### Legacy aliases

The `wt` command name now belongs to [worktrunk](https://worktrunk.dev), so Grove's old `wtab`, `wta`, `wtls`, `wtrm`, `wtp`, `wtcd`, `wtco`, `wtinfo`, `wtdiff`, `wtrn`, `wtlock`, `wtunlock`, `wtstatus`, and `wtui` shell functions live in `legacy/wt-aliases.sh` (and `.fish`). They load only when you opt in before sourcing the Grove aliases:

```bash
export GROVE_LEGACY_ALIASES=1
source ~/.local/share/grove/git-worktree-aliases.sh
```

Prefer the `grove` verbs: `grove new`, `grove add`, `grove ls`, `grove cd`, `grove rm`, and `grove prune`. The `grove wt <cmd>` sub-dispatch and `grove tab` were removed.

## Environment variables

| Variable | Purpose |
| :------- | :------ |
| `GWT_BASE_BRANCH` | Base branch for `prune`/`diff`/`sync`/`log` (default: `origin/HEAD` or `main`) |
| `GWT_WORKTREE_DIR` | Override the worktree parent directory (git backend, normal layout) |
| `GROVE_WORKTREE_BACKEND` | `git` or `worktrunk`; default is `worktrunk` when `wt` is installed |
| `GROVE_LEGACY_ALIASES` | Set to `1` before sourcing the aliases file to load the archived `wt*` functions |
| `GROVE_EDITOR` | Editor for `grove open` (default: `$EDITOR`, else `code`) |
| `AI_EDITOR` | Override the saved default AI agent for the current environment |
| `GROVE_STATUS_BIN` | Executable experimental Go renderer used by `grove status` and Overview |

The config file contains one validated line, such as `default_ai=codex`. A fresh install always writes it. `default_ai=none` keeps worktree-only commands available while agent launches return setup guidance.
