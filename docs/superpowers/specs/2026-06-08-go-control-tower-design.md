# Go Control Tower Design

## Goal

Rewrite Grove's CLI core in Go and add a Bubble Tea Control Tower as the primary interactive surface.

The MVP should preserve Grove's current job:

- Discover git worktrees.
- Launch Zellij with one tab per worktree.
- Show repo-scoped worktree, agent, PR/CI, stash, and resource status.
- Let the user act quickly: jump to a branch tab, open an agent, create/sync/remove worktrees, open PR status, and run commands in a worktree.

Success means `grove tui` opens a fast, readable terminal dashboard where the user can answer:

- Which worktree needs action first?
- Which agent is active in each branch?
- Which PR/check is blocked?
- What command will Grove run if I press Enter?
- Where in the Go code do I edit that behavior?

## Current State

Grove is Bash-first today. The existing architecture is:

```text
grove [path] [ai-editor]
-> launch-grove.sh
-> launch-worktrees.sh --ai <editor> [path]
-> generated Zellij KDL layout
-> git worktrees + LazyGit + agent panes + Overview dashboards
```

The command surface already has a git-style shape:

```text
grove up/status/agents
grove new/add/ls/rm/cd/pick/main/which/root
grove run/exec/sync/pr/mv/log/open/info/diff/rename/prune
grove go/agent
```

The rewrite should keep this mental model. The Go CLI must still support scriptable commands, not force every workflow through the TUI.

## MVP Scope

Build the Go path in parallel with the Bash path.

MVP includes:

- `cmd/grove`: Go entrypoint.
- Scriptable commands for the most-used worktree and workspace verbs.
- `grove tui`: Bubble Tea Control Tower.
- Go services for worktree discovery, status scoring, Zellij session control, PR/CI lookup, and agent process lookup.
- A compatibility path for the current Zellij layout behavior.
- Pattern docs inside the repo so each package explains its design pattern and edit point.

MVP excludes:

- Removing the Bash installer.
- Replacing every shell alias.
- Rewriting every existing status script.
- Remote/SSH hosting with Wish.
- Plugin marketplace or third-party extension API.

## Domain Model

Lead with domain concepts before folders.

### Aggregates

- `Workspace`: one git repository plus all discovered worktrees.
- `Worktree`: branch path, HEAD, dirty state, upstream state, lock state.
- `ControlTower`: the dashboard state assembled from worktrees, agents, PRs, checks, stashes, resources, and sessions.

### Entities

- `AgentSession`: running `claude`, `gemini`, `opencode`, or `codex` process tied to cwd and branch when detectable.
- `PullRequest`: branch-linked PR with review and check state.
- `ZellijSession`: session name, active tab, tab list, running state.
- `Action`: a user-triggered operation like `GoToTab`, `OpenAgent`, `CreatePR`, `SyncBranch`, or `OpenDiff`.

### Value Objects

- `BranchName`
- `WorktreePath`
- `RepoRoot`
- `BaseBranch`
- `AIEditor`
- `CheckState`
- `NextAction`
- `PatternName`

### Domain Events

- `WorkspaceScanned`
- `WorktreeChanged`
- `AgentDetected`
- `PRStatusLoaded`
- `ChecksFailed`
- `NextActionSelected`
- `ZellijActionRequested`

## Control Tower UX

The first screen is operational, not decorative.

```text
Grove Control Tower                    repo: grove  base: main  ai: codex

Worktrees                Needs Action                         Details
> feat/go-tui            1. fix/install: CI failed            Pattern: Mediator
  main clean                next: open checks                 Agent: codex active
  fix/install ci fail     2. docs/spec: dirty files           PR: draft missing
  docs/spec dirty           next: open diff                   Zellij: running

j/k move  enter act  g go tab  a agent  n new  s sync  p pattern  ? help
```

Views:

- `Overview`: worktree list, needs-action queue, selected detail.
- `Action`: confirm and run one action.
- `Form`: create worktree, add existing branch, choose agent, create PR.
- `Pattern`: markdown explanation of the selected package's design pattern.
- `Help`: keybindings and command examples.

## Charm Stack

Use Charm tools where they serve Grove's domain.

| Tool | Role |
| --- | --- |
| Bubble Tea v2 | Main TUI runtime: `Model -> Update -> View`. |
| Bubbles v2 | List, table, viewport, spinner, help, textinput, filepicker, progress. |
| Lip Gloss v2 | Theme, layout, borders, width-aware rendering. |
| Huh v2 | Forms for `new`, `add`, `sync`, `pr`, `agent`, and destructive confirmations. |
| Glamour | Render markdown pattern docs and help pages inside the TUI. |
| Log | File logging for debug output so the TUI never writes noise to stdout. |
| Harmonica | Optional progress animation for long-running fetch/rebase/check operations. |

Do not use Wish in the MVP because Grove is a local terminal workspace, not an SSH app. Keep Gum out of the Go runtime; it remains useful only for shell-script compatibility.

## Package Shape

```text
cmd/grove/
  main.go

internal/app/
  service.go              # Facade: user-facing use cases
  actions.go              # Command pattern: executable operations

internal/domain/workspace/
  workspace.go
  worktree.go
  status.go

internal/domain/agent/
  session.go
  detector.go

internal/domain/review/
  pull_request.go
  checks.go

internal/domain/session/
  zellij.go

internal/adapters/git/
  client.go

internal/adapters/github/
  gh.go

internal/adapters/zellij/
  client.go
  layout.go

internal/adapters/process/
  process.go

internal/tui/controltower/
  model.go
  update.go
  view.go
  messages.go
  keymap.go

internal/tui/components/
  worktree_list.go
  action_queue.go
  detail_panel.go
  pattern_viewer.go

internal/tui/forms/
  new_worktree.go
  sync_branch.go
  create_pr.go

internal/tui/theme/
  theme.go

internal/docs/patterns/
  adapter.md
  command.md
  mediator.md
  strategy.md
```

## Pattern Catalog

Use design patterns as editable guide rails, not ceremony.

| Pattern | Grove usage |
| --- | --- |
| Factory Method | Build command handlers from CLI verbs. |
| Abstract Factory | Build TUI components from selected theme and terminal capability profile. |
| Builder | Build Zellij layout plans from workspace state. |
| Prototype | Clone default pane/tab templates for each worktree. |
| Singleton | One app config instance per process, passed explicitly. Avoid package globals. |
| Adapter | Wrap `git`, `gh`, `zellij`, and process inspection behind interfaces. |
| Bridge | Separate domain use cases from CLI/TUI presentation. |
| Composite | Model workspace layout as workspace -> tabs -> panes. |
| Decorator | Add timing/logging/color around actions without changing action logic. |
| Facade | `app.Service` exposes high-level Grove use cases. |
| Flyweight | Reuse immutable styles, keymaps, table columns, and pattern metadata. |
| Proxy | Cache expensive `gh` and process lookups during a refresh interval. |
| Chain of Responsibility | Resolve next action by priority: failed CI -> dirty files -> behind upstream -> missing PR -> idle. |
| Command | Represent user operations as `Action` values with `Run(context.Context)`. |
| Iterator | Iterate worktrees and action queue in stable display order. |
| Mediator | Control Tower model coordinates components, messages, and selected action. |
| Memento | Save optional session snapshots and last selected worktree. |
| Observer | Refresh loop publishes status snapshots into Bubble Tea messages. |
| State | TUI modes: overview, action, form, pattern, help. |
| Strategy | Swap scoring policies for `NextAction`. |
| Template Method | Shared command lifecycle: validate -> plan -> confirm -> run -> report. |
| Visitor | Render domain state as table rows, details, JSON, or markdown. |

Each pattern should be named in the relevant package doc, with a short "edit here" note.

## Data Flow

```text
CLI args
-> app.Service
-> domain use case
-> adapters: git / gh / zellij / process
-> domain snapshot
-> TUI message
-> ControlTower model
-> Lip Gloss view
-> selected Action
-> app.Service
```

External commands run through `context.Context` with timeouts. Every adapter returns typed errors that the TUI can render and the CLI can print.

## Scriptability

Interactive TUI must not break CLI habits.

- `grove status --json` should print machine-readable state.
- `grove ls` should stay line-oriented.
- `grove run <branch> -- <cmd>` should preserve exit codes.
- `grove tui` owns the full-screen Bubble Tea mode.
- Debug logs go to a file when `GROVE_DEBUG` is set.

## Error Handling

- Wrap external command failures with command, cwd, exit code, and stderr summary.
- Respect `context.Context` cancellation.
- TUI actions show a preview before destructive operations.
- Destructive actions require Huh confirmation.
- Missing optional tools degrade: no `gh` means PR/CI panels show unavailable, not fatal.
- Zellij unavailable blocks workspace launch but not worktree status commands.

## Testing

Unit tests:

- Domain scoring and `NextAction` strategy.
- Git porcelain parser.
- Zellij layout builder.
- Command/action lifecycle.

Integration-style tests:

- Temporary git repos with multiple worktrees.
- Stub `git`, `gh`, `zellij`, and process adapters.
- Bubble Tea model update tests for navigation and action selection.

Snapshot tests:

- Key TUI views at 80, 120, and 160 columns.
- JSON output for `grove status --json`.

## Migration Plan

1. Scaffold Go module and domain/adapters without replacing Bash commands.
2. Implement read-only `grove status --json`.
3. Implement `grove tui` Control Tower using read-only state.
4. Add safe actions: `go`, `agent`, `open`, `run`.
5. Add guarded actions: `new`, `add`, `sync`, `pr`, `rm`.
6. Switch installer to prefer Go binary while keeping Bash compatibility.
7. Retire duplicated Bash logic only after Go commands have coverage.

## Source Ledger

- Local repo: `README.md`, `docs/commands.md`, `docs/architecture.md`, `git-worktree.sh`, `launch-worktrees.sh`.
- Charm docs, current as checked on June 8, 2026:
  - https://charm.land/blog/v2/
  - https://charm.land/libs/
  - https://github.com/charmbracelet/bubbles
  - https://github.com/charmbracelet/huh
  - https://github.com/charmbracelet/glow
  - https://superfile.dev/

Confidence: 85%. The domain split is repo-backed. The Charm API details are current-source-backed, but exact import paths and minor APIs should be verified again during implementation with `go doc` after dependencies are installed.
