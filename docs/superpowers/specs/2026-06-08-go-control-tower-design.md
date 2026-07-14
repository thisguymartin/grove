# Thin Go Status Engine Design

## Goal

Keep Grove as a small terminal workspace orchestrator. Zellij remains the interface; Go provides a typed, read-only status snapshot and concise rendering instead of a second full-screen TUI.

Success means a developer can run `grove`, resume the existing repository session, see which worktree needs attention, and jump to it without losing a running agent or navigating a dashboard application.

## Product Flow

```text
grove
-> attach to the repository's Zellij session when it exists
-> otherwise generate the worktree layout and create the session

git + gh + zellij
-> app.Service
-> Workspace snapshot
-> compact text | full text | JSON
-> one Zellij Overview pane
```

`grove up --fresh` is the explicit escape hatch for replacing a session. `grove go <branch>` focuses the named tab in a background session before attaching.

## Compact Overview

The default Overview is one pane and shows only actionable repository state:

```text
grove  base: main  4 worktrees  updated 10:42

NEEDS ATTENTION
  feat/auth       checks failed        -> grove go feat/auth
  fix/login       3 dirty files        -> grove go fix/login

WORKTREES
  BRANCH          GIT          PR/CHECKS      AGENT
  main            clean        -              codex
  feat/auth       ahead 2      failed         claude
```

Priority order is failed checks, dirty files, behind base, ahead with no PR, merged worktree, then idle. Missing optional integrations produce unknown state rather than guessed actions.

At narrow widths, keep branch, git state, and next action. Add PR/check and agent columns only when space exists. Color may reinforce state but never carries meaning by itself.

## Scope

Included:

- Preserve the existing Bash installer and worktree commands.
- Reuse the typed Go workspace, git, GitHub, and process work already present.
- Add repo-scoped Zellij pane discovery.
- Add compact text, full text, and versioned JSON renderers.
- Make shell help and completions progressively disclose advanced commands.
- Keep the Go binary experimental behind `GROVE_STATUS_BIN` until packaging is designed.

Excluded:

- Bubble Tea, Bubbles, Lip Gloss, Huh, Glamour, or other TUI dependencies.
- Forms, themes, pattern viewers, state machines, or action frameworks.
- Installer changes, release binaries, or new deployment automation.
- Removing legacy `wt*` compatibility commands.

## Domain Model

- `Workspace`: repository root, base branch, worktrees, integration health, statuses, and ordered next actions.
- `WorktreeStatus`: dirty-file count, ahead/behind counts, merged state, PR/check state, and detected agent.
- `NextAction`: one deterministic recommendation derived from repository state.
- `IntegrationHealth`: available or unavailable state for GitHub and Zellij, including a diagnostic reason for full and JSON output.

The domain contains status facts and prioritization only. It does not model UI views or interactive forms.

## Interfaces

```text
grove
grove up [--fresh] [ai-editor] [path]
grove go <branch>
grove status [path] [--full | --json]
grove help [--all]
GROVE_STATUS_BIN=/absolute/path/to/dev-binary
```

`--full` and `--json` are mutually exclusive. JSON schema version 1 contains generation time, repository metadata, integration health, worktree statuses, and next actions.

## Error Handling

- Git discovery failures are fatal and return exit code 1.
- Invalid CLI combinations return exit code 2 with corrective usage.
- GitHub and Zellij failures degrade to unknown integration state and do not create speculative actions.
- External Git, Zellij, and GitHub calls use bounded context timeouts.
- Unknown branches return exit code 1 and suggest `grove pick`.

## Testing

- Fake-Zellij tests for attach, fresh replacement, background tab focus, and missing sessions.
- Shell tests for concise/full help, completion parity, legacy aliases, and parent-shell navigation.
- Layout tests for one Overview pane, the experimental binary hook, and the fallback renderer.
- Go tests for adapter degradation, action scoring, JSON schema, and 80/120/160-column rendering.
- Existing shell and Go regression suites remain green throughout the migration.
