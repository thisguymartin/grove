# Command Reference

Canonical command reference for Grove. Keep this file as the source of truth for CLI examples and worktree helpers.

Grove now uses a single, git-style entry point: **`grove <verb>`** — like `git add` / `git commit`. One mental model, all discoverable via `grove help`. The old `wt*` aliases and `grove wt <cmd>` still work (see [Back-compat](#back-compat)).

## Workspace

```bash
grove up [ai-editor] [path]    # Launch Zellij, one tab per worktree (was bare `grove`)
grove status [path]            # Live worktree status dashboard
grove agents                   # Live dashboard of running AI agents
```

`ai-editor` is one of `claude | gemini | opencode | codex`. Without an explicit value, Grove uses `AI_EDITOR`, then `default_ai` from `${XDG_CONFIG_HOME:-$HOME/.config}/grove/config`. Manual checkouts without a config retain the legacy `opencode` fallback.

## Worktrees

| Command | Description |
| :------ | :---------- |
| `grove new <branch>` | Create a new branch + worktree |
| `grove add <branch>` | Add a worktree for an existing branch |
| `grove ls` | List all worktrees |
| `grove rm <branch>` | Remove a worktree (prompts to delete branch) |
| `grove cd <branch>` | Jump into a worktree (changes shell cwd) |
| `grove pick` | Pick a worktree interactively (fzf, falls back to a numbered menu), then cd into it |
| `grove main` | Jump into the main worktree (changes shell cwd) |
| `grove which <branch>` | Print a worktree's path |
| `grove root` | Print the main worktree path |
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
| `grove tab [--layout-only]` | Launch Zellij tabs (or print the layout) |

> `grove cd`, `grove pick`, and `grove main` change the **calling shell's** cwd, so they run
> inside the `grove()` shell function (sourced from `git-worktree-aliases.sh`). A subprocess
> can't `cd` for you — that's why these are special-cased. `grove pick` lists each worktree
> with the **branch name in color** followed by its **path**; running `grove pick` (the raw
> subcommand) just prints the chosen path.

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

Nothing old breaks — these all still work:

```bash
grove .                        # launch with the saved default agent
grove claude [path]            # launch with Claude
grove wt <cmd>                 # old worktree sub-dispatch
```

Shell aliases from `git-worktree-aliases.sh` (or `.fish`):

| Command | Description |
| :------ | :---------- |
| `wtab <branch>` | Create a new branch + worktree |
| `wta <branch>` | Add worktree for an existing branch |
| `wtls` | List all worktrees |
| `wtrm <path>` | Remove a worktree |
| `wtp [base]` | Prune merged/squash-merged/rebased worktrees |
| `wtco <branch>` / `wtcd <branch>` | `cd` into a worktree by branch name |
| `wtinfo [branch]` | Show path, HEAD, ahead/behind, dirty status |
| `wtdiff [branch]` | Show diff vs base branch |
| `wtrn <old> <new>` | Rename a worktree branch |
| `wtlock <path>` / `wtunlock <path>` | Lock / unlock a worktree |
| `wtui [path]` | Launch Zellij with one tab per worktree |
| `wtstatus [path]` | Show live worktree status dashboard |
| `zj-kill` | Kill all Zellij sessions |

## Environment variables

| Variable | Purpose |
| :------- | :------ |
| `GWT_BASE_BRANCH` | Base branch for `prune`/`diff`/`sync`/`log` (default: `origin/HEAD` or `main`) |
| `GWT_WORKTREE_DIR` | Override the worktree parent directory |
| `GROVE_EDITOR` | Editor for `grove open` (default: `$EDITOR`, else `code`) |
| `AI_EDITOR` | Override the saved default AI agent for the current environment |

The config file contains one validated line, such as `default_ai=codex`. A fresh install always writes it. `default_ai=none` keeps worktree-only commands available while agent launches return setup guidance.
