# Product

## Register

product

## Users

Grove is for terminal-first developers, usually solo developers or small teams, who work across several git branches at once. They are already comfortable with git, worktrees, shells, and keyboard-driven tools. They use Grove while actively coding and need to move between branches and AI agents without losing context or stopping running work.

## Product Purpose

Grove turns one repository into one persistent Zellij workspace with one tab per worktree. It should make launching, resuming, and navigating multi-branch work feel immediate while keeping git, LazyGit, the selected AI agent, and a workbench shell visible through familiar terminal primitives.

Success means a developer can run `grove`, resume the correct repository session, see which branch needs attention, and jump to it without learning or operating a separate dashboard application.

## Brand Personality

Focused, direct, quiet. Grove should feel like a well-arranged workbench: opinionated enough to remove setup, familiar enough to disappear during use, and concise enough to keep attention on the code.

## Anti-references

- Full-screen control-tower applications that duplicate Zellij's navigation and interaction model.
- Observability dashboards that show every available metric before identifying what needs action.
- Verbose CLIs that expose compatibility and maintenance commands as if they were daily workflows.
- Mandatory configuration systems, decorative motion, and UI frameworks that do not improve the core worktree loop.

## Design Principles

1. **Zellij is the interface.** Add small, composable status and navigation helpers instead of building a second terminal UI.
2. **Resume before replacing.** Preserve running sessions and agents by default; destructive reset behavior must be explicit.
3. **Show the next action.** Prioritize blocked or changed worktrees and keep healthy state quiet.
4. **Reveal depth on demand.** Daily commands and compact status come first; advanced commands and diagnostics remain available without competing for attention.
5. **Compatibility stays invisible.** Keep legacy workflows working, but let one canonical command model drive help, completion, and documentation.

## Accessibility & Inclusion

- Every status must remain understandable without color.
- Compact output must remain usable at 80 columns and with long branch names.
- All workflows must be keyboard-only and use familiar shell and Zellij conventions.
- Errors must say what failed and how to recover.
- Avoid decorative animation, rapid refresh, or output that repeatedly steals focus.
