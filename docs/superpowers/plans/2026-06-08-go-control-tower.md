# Go Control Tower Implementation Plan (Superseded)

> Superseded by [`../specs/2026-06-08-go-control-tower-design.md`](../specs/2026-06-08-go-control-tower-design.md). Grove keeps Zellij as the interface and ships only a thin, read-only Go status engine. The Bubble Tea, forms, themes, and full-screen tasks below are intentionally cancelled and retained only as historical context.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Convert Grove's core CLI path to Go and add a Bubble Tea Control Tower TUI while keeping the current Bash/Zellij workflow usable during migration.

**Architecture:** Keep domain rules independent of the terminal UI. Flow: CLI args -> `app.Service` facade -> domain aggregates -> adapters for `git`, `gh`, `zellij`, and processes -> snapshots -> CLI JSON/line output or Bubble Tea messages -> Control Tower view -> domain `Action` values. Shell scripts remain as compatibility entrypoints until the Go binary covers their behavior with tests.

**Tech Stack:** Go 1.26+, standard-library command dispatch, Charm Bubble Tea v2, Bubbles v2, Lip Gloss v2, Huh v2, Glamour, Charm Log, Git CLI, GitHub CLI, Zellij.

---

## Design Inputs

- Use `docs/superpowers/specs/2026-06-08-go-control-tower-design.md` as the source of truth.
- Preserve the current mental model from `docs/commands.md`.
- Keep `launch-grove.sh`, `launch-worktrees.sh`, `git-worktree.sh`, and existing dashboard scripts working while the Go path grows beside them.
- Do not introduce Cobra in the first pass. The CLI shape is small enough for a testable stdlib dispatcher, and avoiding another dependency keeps the first migration narrower.
- Fetch Charm dependencies only when the first TUI task begins. Core domain and adapter tests should pass before adding TUI dependencies.

## File Structure

Create this Go structure over the tasks below:

```text
go.mod
go.sum

cmd/grove/
  main.go
  main_test.go

internal/app/
  service.go
  service_test.go
  actions.go
  actions_test.go

internal/domain/workspace/
  workspace.go
  worktree.go
  status.go
  status_test.go

internal/domain/agent/
  session.go

internal/domain/review/
  pull_request.go
  checks.go

internal/domain/session/
  zellij.go

internal/adapters/git/
  client.go
  client_test.go
  porcelain.go
  porcelain_test.go
  testdata/worktree-list-porcelain.txt

internal/adapters/github/
  gh.go
  gh_test.go

internal/adapters/process/
  process.go
  process_test.go

internal/adapters/zellij/
  client.go
  layout.go
  layout_test.go

internal/tui/controltower/
  model.go
  model_test.go
  update.go
  view.go
  view_test.go
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

## Execution Rules

- Run tests after each task with the command listed in that task.
- Keep generated output and local caches out of git.
- Use `context.Context` in every external adapter method.
- Do not print debug logs to TUI stdout. Use `GROVE_DEBUG` with Charm Log once logging is added.
- Use these commit boundaries exactly as checkpoints. Commit bodies must explain what changed and why; do not add co-author or AI attribution trailers.

---

## Task 1: Scaffold Go Module And Scriptable CLI Dispatcher

**Purpose:** Establish a testable Go entrypoint without changing existing shell entrypoints.

**Files:**

- Create `go.mod`
- Create `cmd/grove/main.go`
- Create `cmd/grove/main_test.go`

- [ ] **Step 1: Initialize module**

Run:

```bash
go mod init github.com/thisguymartin/grove
```

Expected:

```text
go: creating new go.mod: module github.com/thisguymartin/grove
```

- [ ] **Step 2: Create failing CLI dispatcher tests**

Create `cmd/grove/main_test.go`:

```go
package main

import (
	"bytes"
	"context"
	"strings"
	"testing"
)

func TestRunHelpPrintsUsage(t *testing.T) {
	var stdout bytes.Buffer
	var stderr bytes.Buffer

	code := run(context.Background(), []string{"help"}, &stdout, &stderr)
	if code != 0 {
		t.Fatalf("run help exit code = %d, want 0; stderr=%q", code, stderr.String())
	}

	output := stdout.String()
	for _, want := range []string{"Usage:", "grove status --json", "grove tui", "grove ls"} {
		if !strings.Contains(output, want) {
			t.Fatalf("help output missing %q:\n%s", want, output)
		}
	}
}

func TestRunVersionPrintsVersion(t *testing.T) {
	var stdout bytes.Buffer
	var stderr bytes.Buffer

	code := run(context.Background(), []string{"version"}, &stdout, &stderr)
	if code != 0 {
		t.Fatalf("run version exit code = %d, want 0; stderr=%q", code, stderr.String())
	}

	if got := strings.TrimSpace(stdout.String()); got == "" || got == "dev" {
		t.Fatalf("version output = %q, want non-empty version label", got)
	}
}

func TestRunUnknownCommandReportsError(t *testing.T) {
	var stdout bytes.Buffer
	var stderr bytes.Buffer

	code := run(context.Background(), []string{"wat"}, &stdout, &stderr)
	if code != 2 {
		t.Fatalf("unknown command exit code = %d, want 2", code)
	}
	if !strings.Contains(stderr.String(), `unknown command "wat"`) {
		t.Fatalf("stderr missing unknown command:\n%s", stderr.String())
	}
	if stdout.Len() != 0 {
		t.Fatalf("stdout = %q, want empty", stdout.String())
	}
}
```

- [ ] **Step 3: Verify tests fail**

Run:

```bash
go test ./cmd/grove
```

Expected:

```text
no Go files in .../cmd/grove
```

or:

```text
undefined: run
```

- [ ] **Step 4: Implement the dispatcher**

Create `cmd/grove/main.go`:

```go
package main

import (
	"context"
	"fmt"
	"io"
	"os"
	"strings"
)

var version = "0.1.0-dev"

func main() {
	os.Exit(run(context.Background(), os.Args[1:], os.Stdout, os.Stderr))
}

func run(ctx context.Context, args []string, stdout io.Writer, stderr io.Writer) int {
	_ = ctx

	if len(args) == 0 {
		printUsage(stdout)
		return 0
	}

	switch args[0] {
	case "help", "-h", "--help":
		printUsage(stdout)
		return 0
	case "version", "--version":
		fmt.Fprintln(stdout, version)
		return 0
	case "status", "ls", "tui":
		fmt.Fprintf(stderr, "%s is not wired yet\n", args[0])
		return 2
	default:
		fmt.Fprintf(stderr, "unknown command %q\n", args[0])
		printShortUsage(stderr)
		return 2
	}
}

func printUsage(w io.Writer) {
	fmt.Fprintln(w, strings.TrimSpace(`
Usage:
  grove status --json
  grove ls
  grove tui
  grove version
  grove help

Experimental Go CLI for Grove. Bash launch scripts remain available during migration.
`))
	fmt.Fprintln(w)
}

func printShortUsage(w io.Writer) {
	fmt.Fprintln(w, "Run `grove help` for available commands.")
}
```

- [ ] **Step 5: Verify**

Run:

```bash
go test ./cmd/grove
go test ./...
```

Expected:

```text
ok  	github.com/thisguymartin/grove/cmd/grove
```

- [ ] **Commit boundary**

Commit:

```bash
git add go.mod cmd/grove/main.go cmd/grove/main_test.go
git commit -m "chore: scaffold go cli entrypoint" \
  -m "Add an experimental Go module and testable grove command dispatcher." \
  -m "- Adds a stdlib-based CLI entrypoint for help, version, and command routing." \
  -m "- Keeps existing Bash launch scripts untouched while the Go path is built in parallel."
```

---

## Task 2: Model Workspace And Parse Git Worktree Porcelain

**Purpose:** Make `git worktree list --porcelain` a typed domain input.

**Files:**

- Create `internal/domain/workspace/workspace.go`
- Create `internal/domain/workspace/worktree.go`
- Create `internal/adapters/git/porcelain.go`
- Create `internal/adapters/git/porcelain_test.go`
- Create `internal/adapters/git/testdata/worktree-list-porcelain.txt`

- [ ] **Step 1: Add porcelain fixture**

Create `internal/adapters/git/testdata/worktree-list-porcelain.txt`:

```text
worktree /repo/grove
HEAD 1111111111111111111111111111111111111111
branch refs/heads/main

worktree /repo/.worktrees/feat-go-tui
HEAD 2222222222222222222222222222222222222222
branch refs/heads/feat/go-tui

worktree /repo/.worktrees/detached-check
HEAD 3333333333333333333333333333333333333333
detached

worktree /repo/.worktrees/locked
HEAD 4444444444444444444444444444444444444444
branch refs/heads/fix/install
locked maintenance window
```

- [ ] **Step 2: Create failing parser test**

Create `internal/adapters/git/porcelain_test.go`:

```go
package git

import (
	"os"
	"testing"
)

func TestParseWorktreePorcelain(t *testing.T) {
	input, err := os.ReadFile("testdata/worktree-list-porcelain.txt")
	if err != nil {
		t.Fatal(err)
	}

	got, err := ParseWorktreePorcelain(string(input))
	if err != nil {
		t.Fatalf("ParseWorktreePorcelain returned error: %v", err)
	}

	if len(got) != 4 {
		t.Fatalf("len(worktrees) = %d, want 4", len(got))
	}

	tests := []struct {
		index  int
		path   string
		branch string
		head   string
		locked bool
	}{
		{0, "/repo/grove", "main", "1111111111111111111111111111111111111111", false},
		{1, "/repo/.worktrees/feat-go-tui", "feat/go-tui", "2222222222222222222222222222222222222222", false},
		{2, "/repo/.worktrees/detached-check", "", "3333333333333333333333333333333333333333", false},
		{3, "/repo/.worktrees/locked", "fix/install", "4444444444444444444444444444444444444444", true},
	}

	for _, tt := range tests {
		wt := got[tt.index]
		if string(wt.Path) != tt.path {
			t.Fatalf("worktree[%d].Path = %q, want %q", tt.index, wt.Path, tt.path)
		}
		if string(wt.Branch) != tt.branch {
			t.Fatalf("worktree[%d].Branch = %q, want %q", tt.index, wt.Branch, tt.branch)
		}
		if wt.Head != tt.head {
			t.Fatalf("worktree[%d].Head = %q, want %q", tt.index, wt.Head, tt.head)
		}
		if wt.Locked != tt.locked {
			t.Fatalf("worktree[%d].Locked = %v, want %v", tt.index, wt.Locked, tt.locked)
		}
	}
}
```

- [ ] **Step 3: Verify failure**

Run:

```bash
go test ./internal/adapters/git
```

Expected:

```text
undefined: ParseWorktreePorcelain
```

- [ ] **Step 4: Add domain types**

Create `internal/domain/workspace/worktree.go`:

```go
package workspace

type BranchName string
type WorktreePath string

type Worktree struct {
	Path   WorktreePath `json:"path"`
	Branch BranchName  `json:"branch"`
	Head   string      `json:"head"`
	Locked bool        `json:"locked"`
}

func (w Worktree) DisplayName() string {
	if w.Branch != "" {
		return string(w.Branch)
	}
	return "detached@" + shortSHA(w.Head)
}

func shortSHA(value string) string {
	if len(value) <= 7 {
		return value
	}
	return value[:7]
}
```

Create `internal/domain/workspace/workspace.go`:

```go
package workspace

type RepoRoot string

type Workspace struct {
	Root      RepoRoot   `json:"root"`
	Base      BranchName `json:"base"`
	Worktrees []Worktree `json:"worktrees"`
}
```

- [ ] **Step 5: Implement parser**

Create `internal/adapters/git/porcelain.go`:

```go
package git

import (
	"bufio"
	"strings"

	"github.com/thisguymartin/grove/internal/domain/workspace"
)

func ParseWorktreePorcelain(input string) ([]workspace.Worktree, error) {
	var out []workspace.Worktree
	current := workspace.Worktree{}

	flush := func() {
		if current.Path == "" {
			return
		}
		out = append(out, current)
		current = workspace.Worktree{}
	}

	scanner := bufio.NewScanner(strings.NewReader(input))
	for scanner.Scan() {
		line := scanner.Text()
		if line == "" {
			flush()
			continue
		}

		key, value, _ := strings.Cut(line, " ")
		switch key {
		case "worktree":
			flush()
			current.Path = workspace.WorktreePath(value)
		case "HEAD":
			current.Head = value
		case "branch":
			current.Branch = workspace.BranchName(strings.TrimPrefix(value, "refs/heads/"))
		case "detached":
			current.Branch = ""
		case "locked":
			current.Locked = true
		}
	}
	if err := scanner.Err(); err != nil {
		return nil, err
	}
	flush()

	return out, nil
}
```

- [ ] **Step 6: Verify**

Run:

```bash
go test ./internal/adapters/git
go test ./...
```

Expected:

```text
ok  	github.com/thisguymartin/grove/internal/adapters/git
```

- [ ] **Commit boundary**

Commit:

```bash
git add internal/domain/workspace internal/adapters/git
git commit -m "feat: parse git worktree porcelain" \
  -m "Model Grove worktrees as typed domain data and parse git's porcelain output." \
  -m "- Adds Workspace and Worktree value types for the Go migration." \
  -m "- Adds parser coverage for normal, detached, and locked worktrees."
```

---

## Task 3: Add Git Adapter And Workspace Status Service

**Purpose:** Turn real `git` output into a workspace snapshot with testable boundaries.

**Files:**

- Create `internal/adapters/git/client.go`
- Create `internal/adapters/git/client_test.go`
- Create `internal/app/service.go`
- Create `internal/app/service_test.go`

- [ ] **Step 1: Create failing service test with fake Git client**

Create `internal/app/service_test.go`:

```go
package app

import (
	"context"
	"testing"

	"github.com/thisguymartin/grove/internal/domain/workspace"
)

type fakeGit struct {
	root      workspace.RepoRoot
	base      workspace.BranchName
	worktrees []workspace.Worktree
}

func (f fakeGit) Root(context.Context, string) (workspace.RepoRoot, error) {
	return f.root, nil
}

func (f fakeGit) BaseBranch(context.Context, workspace.RepoRoot) (workspace.BranchName, error) {
	return f.base, nil
}

func (f fakeGit) Worktrees(context.Context, workspace.RepoRoot) ([]workspace.Worktree, error) {
	return f.worktrees, nil
}

func TestServiceStatusBuildsWorkspace(t *testing.T) {
	svc := NewService(ServiceConfig{
		Git: fakeGit{
			root: "/repo/grove",
			base: "main",
			worktrees: []workspace.Worktree{
				{Path: "/repo/grove", Branch: "main", Head: "abc"},
				{Path: "/repo/.worktrees/feat-go-tui", Branch: "feat/go-tui", Head: "def"},
			},
		},
	})

	got, err := svc.Status(context.Background(), "/repo/grove")
	if err != nil {
		t.Fatalf("Status returned error: %v", err)
	}

	if got.Root != "/repo/grove" {
		t.Fatalf("Root = %q, want /repo/grove", got.Root)
	}
	if got.Base != "main" {
		t.Fatalf("Base = %q, want main", got.Base)
	}
	if len(got.Worktrees) != 2 {
		t.Fatalf("len(Worktrees) = %d, want 2", len(got.Worktrees))
	}
}
```

- [ ] **Step 2: Verify failure**

Run:

```bash
go test ./internal/app
```

Expected:

```text
undefined: NewService
```

- [ ] **Step 3: Implement service facade**

Create `internal/app/service.go`:

```go
package app

import (
	"context"
	"errors"

	"github.com/thisguymartin/grove/internal/domain/workspace"
)

type GitClient interface {
	Root(context.Context, string) (workspace.RepoRoot, error)
	BaseBranch(context.Context, workspace.RepoRoot) (workspace.BranchName, error)
	Worktrees(context.Context, workspace.RepoRoot) ([]workspace.Worktree, error)
}

type ServiceConfig struct {
	Git GitClient
}

type Service struct {
	git GitClient
}

func NewService(cfg ServiceConfig) *Service {
	return &Service{git: cfg.Git}
}

func (s *Service) Status(ctx context.Context, path string) (workspace.Workspace, error) {
	if s.git == nil {
		return workspace.Workspace{}, errors.New("git client is required")
	}

	root, err := s.git.Root(ctx, path)
	if err != nil {
		return workspace.Workspace{}, err
	}

	base, err := s.git.BaseBranch(ctx, root)
	if err != nil {
		return workspace.Workspace{}, err
	}

	worktrees, err := s.git.Worktrees(ctx, root)
	if err != nil {
		return workspace.Workspace{}, err
	}

	return workspace.Workspace{
		Root:      root,
		Base:      base,
		Worktrees: worktrees,
	}, nil
}
```

- [ ] **Step 4: Create failing Git adapter tests**

Create `internal/adapters/git/client_test.go` with tests that inject a fake command runner:

```go
package git

import (
	"context"
	"fmt"
	"strings"
	"testing"
)

func TestClientRootUsesRevParse(t *testing.T) {
	runner := &fakeRunner{
		output: map[string]string{
			"git -C /repo/grove rev-parse --show-toplevel": "/repo/grove\n",
		},
	}
	client := NewClient(runner)

	got, err := client.Root(context.Background(), "/repo/grove")
	if err != nil {
		t.Fatalf("Root returned error: %v", err)
	}
	if got != "/repo/grove" {
		t.Fatalf("Root = %q, want /repo/grove", got)
	}
}

func TestClientWorktreesParsesPorcelain(t *testing.T) {
	runner := &fakeRunner{
		output: map[string]string{
			"git -C /repo/grove worktree list --porcelain": strings.Join([]string{
				"worktree /repo/grove",
				"HEAD abc",
				"branch refs/heads/main",
				"",
			}, "\n"),
		},
	}
	client := NewClient(runner)

	got, err := client.Worktrees(context.Background(), "/repo/grove")
	if err != nil {
		t.Fatalf("Worktrees returned error: %v", err)
	}
	if len(got) != 1 || got[0].Branch != "main" {
		t.Fatalf("Worktrees = %#v, want main worktree", got)
	}
}

type fakeRunner struct {
	output map[string]string
	calls  []string
}

func (f *fakeRunner) Run(_ context.Context, name string, args ...string) ([]byte, error) {
	parts := append([]string{name}, args...)
	key := strings.Join(parts, " ")
	f.calls = append(f.calls, key)

	out, ok := f.output[key]
	if !ok {
		return nil, fmt.Errorf("missing fake output for %s", key)
	}
	return []byte(out), nil
}
```

- [ ] **Step 5: Implement Git adapter with command runner**

Create `internal/adapters/git/client.go` with this shape:

```go
package git

import (
	"context"
	"fmt"
	"os/exec"
	"strings"
	"time"

	"github.com/thisguymartin/grove/internal/domain/workspace"
)

type Runner interface {
	Run(context.Context, string, ...string) ([]byte, error)
}

type ExecRunner struct{}

func (ExecRunner) Run(ctx context.Context, name string, args ...string) ([]byte, error) {
	ctx, cancel := context.WithTimeout(ctx, 10*time.Second)
	defer cancel()

	cmd := exec.CommandContext(ctx, name, args...)
	out, err := cmd.CombinedOutput()
	if err != nil {
		return nil, fmt.Errorf("%s %s: %w: %s", name, strings.Join(args, " "), err, strings.TrimSpace(string(out)))
	}
	return out, nil
}

type Client struct {
	runner Runner
}

func NewClient(runner Runner) *Client {
	if runner == nil {
		runner = ExecRunner{}
	}
	return &Client{runner: runner}
}

func (c *Client) Root(ctx context.Context, path string) (workspace.RepoRoot, error) {
	out, err := c.runner.Run(ctx, "git", "-C", path, "rev-parse", "--show-toplevel")
	if err != nil {
		return "", err
	}
	return workspace.RepoRoot(strings.TrimSpace(string(out))), nil
}

func (c *Client) BaseBranch(ctx context.Context, root workspace.RepoRoot) (workspace.BranchName, error) {
	out, err := c.runner.Run(ctx, "git", "-C", string(root), "symbolic-ref", "--short", "refs/remotes/origin/HEAD")
	if err == nil {
		branch := strings.TrimSpace(strings.TrimPrefix(string(out), "origin/"))
		if branch != "" {
			return workspace.BranchName(branch), nil
		}
	}
	return "main", nil
}

func (c *Client) Worktrees(ctx context.Context, root workspace.RepoRoot) ([]workspace.Worktree, error) {
	out, err := c.runner.Run(ctx, "git", "-C", string(root), "worktree", "list", "--porcelain")
	if err != nil {
		return nil, err
	}
	return ParseWorktreePorcelain(string(out))
}
```

- [ ] **Step 6: Verify**

Run:

```bash
go test ./internal/adapters/git ./internal/app
go test ./...
```

Expected:

```text
ok  	github.com/thisguymartin/grove/internal/adapters/git
ok  	github.com/thisguymartin/grove/internal/app
```

- [ ] **Commit boundary**

Commit:

```bash
git add internal/adapters/git/client.go internal/adapters/git/client_test.go internal/app/service.go internal/app/service_test.go
git commit -m "feat: add workspace status service" \
  -m "Introduce the app facade that turns git adapter data into a Grove workspace snapshot." \
  -m "- Adds a context-aware Git adapter around git CLI commands." \
  -m "- Adds service tests with a fake Git client to keep domain behavior independent of shell commands."
```

---

## Task 4: Add Status Scoring Strategy And `status --json`

**Purpose:** Make the CLI answer "what needs action first?" in machine-readable form.

**Files:**

- Create `internal/domain/workspace/status.go`
- Create `internal/domain/workspace/status_test.go`
- Modify `internal/domain/workspace/worktree.go`
- Modify `internal/domain/workspace/workspace.go`
- Modify `internal/app/service.go`
- Modify `internal/app/service_test.go`
- Modify `cmd/grove/main.go`
- Modify `cmd/grove/main_test.go`

- [ ] **Step 1: Create failing scoring tests**

Create `internal/domain/workspace/status_test.go`:

```go
package workspace

import "testing"

func TestScoreNextActionPriority(t *testing.T) {
	input := []WorktreeStatus{
		{Worktree: Worktree{Branch: "docs/spec"}, DirtyFiles: 2},
		{Worktree: Worktree{Branch: "fix/install"}, Checks: CheckStateFailed},
		{Worktree: Worktree{Branch: "feat/go-tui"}, Behind: 3},
		{Worktree: Worktree{Branch: "main"}, Clean: true},
	}

	got := ScoreNextActions(input)
	if len(got) != 4 {
		t.Fatalf("len(actions) = %d, want 4", len(got))
	}
	if got[0].Branch != "fix/install" || got[0].Kind != NextActionOpenChecks {
		t.Fatalf("first action = %#v, want fix/install open checks", got[0])
	}
	if got[1].Branch != "docs/spec" || got[1].Kind != NextActionOpenDiff {
		t.Fatalf("second action = %#v, want docs/spec open diff", got[1])
	}
	if got[2].Branch != "feat/go-tui" || got[2].Kind != NextActionSync {
		t.Fatalf("third action = %#v, want feat/go-tui sync", got[2])
	}
	if got[3].Kind != NextActionIdle {
		t.Fatalf("last action = %#v, want idle", got[3])
	}
}
```

- [ ] **Step 2: Implement status value objects and strategy**

Create `internal/domain/workspace/status.go`:

```go
package workspace

import "sort"

type CheckState string

const (
	CheckStateUnknown CheckState = "unknown"
	CheckStatePassing CheckState = "passing"
	CheckStatePending CheckState = "pending"
	CheckStateFailed  CheckState = "failed"
)

type NextActionKind string

const (
	NextActionOpenChecks NextActionKind = "open_checks"
	NextActionOpenDiff   NextActionKind = "open_diff"
	NextActionSync       NextActionKind = "sync"
	NextActionCreatePR   NextActionKind = "create_pr"
	NextActionIdle       NextActionKind = "idle"
)

type WorktreeStatus struct {
	Worktree   Worktree   `json:"worktree"`
	Clean      bool       `json:"clean"`
	DirtyFiles int        `json:"dirty_files"`
	Ahead      int        `json:"ahead"`
	Behind     int        `json:"behind"`
	HasPR      bool       `json:"has_pr"`
	Checks     CheckState `json:"checks"`
}

type NextAction struct {
	Branch BranchName     `json:"branch"`
	Kind   NextActionKind `json:"kind"`
	Label  string         `json:"label"`
	Score  int            `json:"score"`
}

func ScoreNextActions(statuses []WorktreeStatus) []NextAction {
	out := make([]NextAction, 0, len(statuses))
	for _, status := range statuses {
		out = append(out, scoreStatus(status))
	}
	sort.SliceStable(out, func(i, j int) bool {
		return out[i].Score > out[j].Score
	})
	return out
}

func scoreStatus(status WorktreeStatus) NextAction {
	branch := status.Worktree.Branch
	switch {
	case status.Checks == CheckStateFailed:
		return NextAction{Branch: branch, Kind: NextActionOpenChecks, Label: "open failed checks", Score: 500}
	case status.DirtyFiles > 0:
		return NextAction{Branch: branch, Kind: NextActionOpenDiff, Label: "review dirty files", Score: 400}
	case status.Behind > 0:
		return NextAction{Branch: branch, Kind: NextActionSync, Label: "sync with base", Score: 300}
	case branch != "main" && branch != "" && !status.HasPR:
		return NextAction{Branch: branch, Kind: NextActionCreatePR, Label: "create pull request", Score: 200}
	default:
		return NextAction{Branch: branch, Kind: NextActionIdle, Label: "idle", Score: 0}
	}
}
```

- [ ] **Step 3: Extend workspace snapshot**

Modify `internal/domain/workspace/workspace.go`:

```go
package workspace

type RepoRoot string

type Workspace struct {
	Root        RepoRoot         `json:"root"`
	Base        BranchName      `json:"base"`
	Worktrees   []Worktree      `json:"worktrees"`
	Statuses    []WorktreeStatus `json:"statuses"`
	NextActions []NextAction    `json:"next_actions"`
}
```

- [ ] **Step 4: Extend service to build clean baseline statuses**

Update `internal/app/service.go` so `Status` creates a `WorktreeStatus` per worktree. For this task, set `Clean: true`, `Checks: CheckStateUnknown`, and `HasPR: branch == base` until GitHub and dirty-file adapters land.

- [ ] **Step 5: Create failing CLI JSON tests**

Extend `cmd/grove/main_test.go` with:

```go
func TestRunStatusJSONPrintsSnapshot(t *testing.T) {
	var stdout bytes.Buffer
	var stderr bytes.Buffer

	code := run(context.Background(), []string{"status", "--json"}, &stdout, &stderr)
	if code != 0 {
		t.Fatalf("status --json exit code = %d, want 0; stderr=%q", code, stderr.String())
	}

	output := stdout.String()
	for _, want := range []string{`"root"`, `"worktrees"`, `"next_actions"`} {
		if !strings.Contains(output, want) {
			t.Fatalf("json output missing %q:\n%s", want, output)
		}
	}
}
```

Adjust `run` to build a real `app.Service` with `git.NewClient(nil)` for normal execution. In the test, allow the current working directory to be used as the repo.

- [ ] **Step 6: Implement `status --json`**

Modify `cmd/grove/main.go`:

- Route `status --json` through `app.Service.Status`.
- Encode `workspace.Workspace` with `json.NewEncoder(stdout).Encode(snapshot)`.
- Return exit code `2` for unsupported `status` flags.
- Return exit code `1` for adapter/runtime errors and print the error to stderr.

- [ ] **Step 7: Verify**

Run:

```bash
go test ./internal/domain/workspace ./internal/app ./cmd/grove
go test ./...
go run ./cmd/grove status --json
```

Expected `go run` shape:

```json
{"root":"/Users/thisguymartin/personal-workspace/grove","base":"main","worktrees":[...],"statuses":[...],"next_actions":[...]}
```

- [ ] **Commit boundary**

Commit:

```bash
git add cmd/grove internal/app internal/domain/workspace
git commit -m "feat: expose workspace status json" \
  -m "Make the Go CLI return a repo-scoped workspace snapshot for scripts and the future TUI." \
  -m "- Adds status scoring for the next-action queue." \
  -m "- Wires grove status --json through the app facade and Git adapter." \
  -m "- Keeps the output machine-readable for shell and editor integrations."
```

---

## Task 5: Add Optional GitHub And Process Adapters

**Purpose:** Enrich snapshots without making optional tools fatal.

**Files:**

- Create `internal/domain/agent/session.go`
- Create `internal/domain/review/pull_request.go`
- Create `internal/domain/review/checks.go`
- Create `internal/adapters/github/gh.go`
- Create `internal/adapters/github/gh_test.go`
- Create `internal/adapters/process/process.go`
- Create `internal/adapters/process/process_test.go`
- Modify `internal/app/service.go`
- Modify `internal/domain/workspace/status.go`

- [ ] **Step 1: Add review and agent value types**

Create `internal/domain/review/pull_request.go`:

```go
package review

type PullRequest struct {
	Branch string `json:"branch"`
	Number int    `json:"number"`
	URL    string `json:"url"`
	State  string `json:"state"`
	Draft  bool   `json:"draft"`
}
```

Create `internal/domain/review/checks.go`:

```go
package review

type CheckRollup struct {
	Branch string `json:"branch"`
	State  string `json:"state"`
}
```

Create `internal/domain/agent/session.go`:

```go
package agent

type Session struct {
	Branch  string `json:"branch"`
	Editor  string `json:"editor"`
	PID     int    `json:"pid"`
	Command string `json:"command"`
}
```

- [ ] **Step 2: Create GitHub adapter tests**

Create `internal/adapters/github/gh_test.go`:

```go
package github

import (
	"context"
	"errors"
	"os/exec"
	"strings"
	"testing"
)

func TestPullRequestsMapsGhJSON(t *testing.T) {
	client := NewClient(&fakeRunner{
		out: []byte(`[{"number":17,"url":"https://github.com/thisguymartin/grove/pull/17","state":"OPEN","isDraft":true,"headRefName":"feat/go-tui"}]`),
	})

	got, err := client.PullRequests(context.Background(), "/repo/grove")
	if err != nil {
		t.Fatalf("PullRequests returned error: %v", err)
	}
	if len(got) != 1 {
		t.Fatalf("len(PRs) = %d, want 1", len(got))
	}
	if got[0].Branch != "feat/go-tui" || got[0].Number != 17 || !got[0].Draft {
		t.Fatalf("PR = %#v, want mapped branch/number/draft", got[0])
	}
}

func TestPullRequestsMissingGHReturnsUnavailable(t *testing.T) {
	client := NewClient(&fakeRunner{err: exec.ErrNotFound})

	got, err := client.PullRequests(context.Background(), "/repo/grove")
	if len(got) != 0 {
		t.Fatalf("PRs = %#v, want empty", got)
	}
	var unavailable UnavailableError
	if !errors.As(err, &unavailable) {
		t.Fatalf("error = %v, want UnavailableError", err)
	}
}

func TestPullRequestsInvalidJSONIncludesCommandContext(t *testing.T) {
	client := NewClient(&fakeRunner{out: []byte(`nope`)})

	_, err := client.PullRequests(context.Background(), "/repo/grove")
	if err == nil {
		t.Fatal("PullRequests error = nil, want JSON error")
	}
	if !strings.Contains(err.Error(), "gh pr list json") {
		t.Fatalf("error = %v, want command context", err)
	}
}

type fakeRunner struct {
	out  []byte
	err  error
	args []string
}

func (f *fakeRunner) Run(_ context.Context, name string, args ...string) ([]byte, error) {
	f.args = append([]string{name}, args...)
	if f.err != nil {
		return nil, f.err
	}
	return f.out, nil
}
```

- [ ] **Step 3: Create process adapter tests**

Create `internal/adapters/process/process_test.go`:

```go
package process

import (
	"context"
	"testing"
)

func TestSessionsReturnsEmptyWhenNoAgentProcessesExist(t *testing.T) {
	client := NewClient(&fakeRunner{out: []byte("100 /bin/zsh\n101 git status\n")})

	got, err := client.Sessions(context.Background())
	if err != nil {
		t.Fatalf("Sessions returned error: %v", err)
	}
	if len(got) != 0 {
		t.Fatalf("Sessions = %#v, want empty", got)
	}
}

func TestSessionsDetectsKnownAgentProcesses(t *testing.T) {
	client := NewClient(&fakeRunner{out: []byte("200 codex\n201 claude --dangerously-skip-permissions\n")})

	got, err := client.Sessions(context.Background())
	if err != nil {
		t.Fatalf("Sessions returned error: %v", err)
	}
	if len(got) != 2 {
		t.Fatalf("len(Sessions) = %d, want 2", len(got))
	}
	if got[0].Editor != "codex" || got[0].PID != 200 {
		t.Fatalf("first session = %#v, want codex pid 200", got[0])
	}
	if got[1].Editor != "claude" || got[1].PID != 201 {
		t.Fatalf("second session = %#v, want claude pid 201", got[1])
	}
}

type fakeRunner struct {
	out []byte
	err error
}

func (f *fakeRunner) Run(context.Context, string, ...string) ([]byte, error) {
	if f.err != nil {
		return nil, f.err
	}
	return f.out, nil
}
```

- [ ] **Step 4: Implement GitHub adapter**

Create `internal/adapters/github/gh.go`:

```go
package github

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"os/exec"
	"strings"

	"github.com/thisguymartin/grove/internal/domain/review"
	"github.com/thisguymartin/grove/internal/domain/workspace"
)

type Runner interface {
	Run(context.Context, string, ...string) ([]byte, error)
}

type UnavailableError struct {
	Tool string
}

func (e UnavailableError) Error() string {
	return e.Tool + " unavailable"
}

type Client struct {
	runner Runner
}

func NewClient(runner Runner) *Client {
	return &Client{runner: runner}
}

func (c *Client) PullRequests(ctx context.Context, root workspace.RepoRoot) ([]review.PullRequest, error) {
	_ = root
	out, err := c.runner.Run(ctx, "gh", "pr", "list", "--json", "number,url,state,isDraft,headRefName")
	if err != nil {
		if errors.Is(err, exec.ErrNotFound) || strings.Contains(strings.ToLower(err.Error()), "executable file not found") {
			return nil, UnavailableError{Tool: "gh"}
		}
		return nil, fmt.Errorf("gh pr list: %w", err)
	}

	var rows []struct {
		Number      int    `json:"number"`
		URL         string `json:"url"`
		State       string `json:"state"`
		Draft       bool   `json:"isDraft"`
		HeadRefName string `json:"headRefName"`
	}
	if err := json.Unmarshal(out, &rows); err != nil {
		return nil, fmt.Errorf("gh pr list json: %w", err)
	}

	prs := make([]review.PullRequest, 0, len(rows))
	for _, row := range rows {
		prs = append(prs, review.PullRequest{
			Branch: row.HeadRefName,
			Number: row.Number,
			URL:    row.URL,
			State:  row.State,
			Draft:  row.Draft,
		})
	}
	return prs, nil
}
```

- [ ] **Step 5: Implement process adapter**

Create `internal/adapters/process/process.go`:

```go
package process

import (
	"bufio"
	"context"
	"strconv"
	"strings"

	"github.com/thisguymartin/grove/internal/domain/agent"
)

type Runner interface {
	Run(context.Context, string, ...string) ([]byte, error)
}

type Client struct {
	runner Runner
}

func NewClient(runner Runner) *Client {
	return &Client{runner: runner}
}

func (c *Client) Sessions(ctx context.Context) ([]agent.Session, error) {
	out, err := c.runner.Run(ctx, "ps", "-axo", "pid=,command=")
	if err != nil {
		return nil, err
	}

	var sessions []agent.Session
	scanner := bufio.NewScanner(strings.NewReader(string(out)))
	for scanner.Scan() {
		pid, command, ok := parseProcessRow(scanner.Text())
		if !ok {
			continue
		}
		if editor := knownEditor(command); editor != "" {
			sessions = append(sessions, agent.Session{PID: pid, Editor: editor, Command: command})
		}
	}
	return sessions, scanner.Err()
}

func parseProcessRow(row string) (int, string, bool) {
	fields := strings.Fields(strings.TrimSpace(row))
	if len(fields) < 2 {
		return 0, "", false
	}
	pid, err := strconv.Atoi(fields[0])
	if err != nil {
		return 0, "", false
	}
	command := strings.TrimSpace(strings.TrimPrefix(strings.TrimSpace(row), fields[0]))
	return pid, command, true
}

func knownEditor(command string) string {
	lower := strings.ToLower(command)
	for _, editor := range []string{"claude", "gemini", "opencode", "codex"} {
		if strings.Contains(lower, editor) {
			return editor
		}
	}
	return ""
}
```

- [ ] **Step 6: Update service snapshot enrichment**

Modify `internal/app/service.go`:

- Add optional `Reviews` and `Agents` interfaces to `ServiceConfig`.
- Call them after Git worktrees are loaded.
- If an optional adapter is unavailable, keep status output with `CheckStateUnknown` and no PRs.
- Set `HasPR` when a pull request branch matches a worktree branch.
- Set `Checks` from GitHub check rollup when available.

- [ ] **Step 7: Verify**

Run:

```bash
go test ./internal/adapters/github ./internal/adapters/process ./internal/app
go test ./...
go run ./cmd/grove status --json
```

Expected when `gh` is unavailable:

```text
status command exits 0 and JSON still includes worktrees
```

- [ ] **Commit boundary**

Commit:

```bash
git add internal/domain/agent internal/domain/review internal/adapters/github internal/adapters/process internal/app internal/domain/workspace
git commit -m "feat: enrich status with optional local signals" \
  -m "Add optional GitHub and process adapters without making local status depend on those tools." \
  -m "- Adds review and agent domain value types." \
  -m "- Treats missing gh or absent agent processes as degraded status data instead of fatal errors." \
  -m "- Connects branch PR/check data to the next-action scoring path."
```

---

## Task 6: Add Read-Only Bubble Tea Control Tower

**Purpose:** Create the first real TUI screen using the status snapshot.

**Files:**

- Modify `go.mod`
- Modify `go.sum`
- Modify `cmd/grove/main.go`
- Create `internal/tui/theme/theme.go`
- Create `internal/tui/controltower/model.go`
- Create `internal/tui/controltower/messages.go`
- Create `internal/tui/controltower/keymap.go`
- Create `internal/tui/controltower/update.go`
- Create `internal/tui/controltower/view.go`
- Create `internal/tui/controltower/model_test.go`
- Create `internal/tui/controltower/view_test.go`

- [ ] **Step 1: Add Charm dependencies**

Run:

```bash
go get charm.land/bubbletea/v2 charm.land/bubbles/v2 charm.land/lipgloss/v2 charm.land/huh/v2 github.com/charmbracelet/glamour github.com/charmbracelet/log
go mod tidy
```

Expected module check:

```bash
go list -m charm.land/bubbletea/v2 charm.land/bubbles/v2 charm.land/lipgloss/v2 charm.land/huh/v2 github.com/charmbracelet/glamour github.com/charmbracelet/log
```

Expected: each module prints with a resolved version. If a Charm package path changed, use `go list -m -versions` and the current official Charm docs before editing imports.

- [ ] **Step 2: Create failing model navigation test**

Create `internal/tui/controltower/model_test.go`:

```go
package controltower

import (
	"testing"

	tea "charm.land/bubbletea/v2"

	"github.com/thisguymartin/grove/internal/domain/workspace"
)

func TestModelSelectionMovesDown(t *testing.T) {
	model := NewModel(workspace.Workspace{
		Root: "/repo/grove",
		Base: "main",
		Statuses: []workspace.WorktreeStatus{
			{Worktree: workspace.Worktree{Branch: "main"}},
			{Worktree: workspace.Worktree{Branch: "feat/go-tui"}},
		},
	})

	updated, _ := model.Update(tea.KeyMsg{Type: tea.KeyDown})
	next := updated.(Model)
	if next.SelectedIndex != 1 {
		t.Fatalf("SelectedIndex = %d, want 1", next.SelectedIndex)
	}
}
```

- [ ] **Step 3: Create failing view test**

Create `internal/tui/controltower/view_test.go`:

```go
package controltower

import (
	"strings"
	"testing"

	"github.com/thisguymartin/grove/internal/domain/workspace"
)

func TestViewShowsControlTowerColumns(t *testing.T) {
	model := NewModel(workspace.Workspace{
		Root: "/repo/grove",
		Base: "main",
		Statuses: []workspace.WorktreeStatus{
			{Worktree: workspace.Worktree{Branch: "feat/go-tui"}, DirtyFiles: 2},
			{Worktree: workspace.Worktree{Branch: "main"}, Clean: true},
		},
		NextActions: []workspace.NextAction{
			{Branch: "feat/go-tui", Kind: workspace.NextActionOpenDiff, Label: "review dirty files", Score: 400},
		},
	})
	model.Width = 100
	model.Height = 28

	view := model.View()
	for _, want := range []string{"Grove Control Tower", "Worktrees", "Needs Action", "Details", "feat/go-tui", "review dirty files"} {
		if !strings.Contains(view, want) {
			t.Fatalf("view missing %q:\n%s", want, view)
		}
	}
}
```

- [ ] **Step 4: Implement TUI model**

Create `internal/tui/controltower/model.go`:

```go
package controltower

import (
	tea "charm.land/bubbletea/v2"

	"github.com/thisguymartin/grove/internal/domain/workspace"
)

type Mode int

const (
	ModeOverview Mode = iota
	ModeHelp
	ModePattern
)

type Model struct {
	Snapshot      workspace.Workspace
	SelectedIndex int
	Width         int
	Height        int
	Mode          Mode
}

func NewModel(snapshot workspace.Workspace) Model {
	return Model{Snapshot: snapshot}
}

func (m Model) Init() tea.Cmd {
	return nil
}
```

Create `internal/tui/controltower/update.go`:

```go
package controltower

import tea "charm.land/bubbletea/v2"

func (m Model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.WindowSizeMsg:
		m.Width = msg.Width
		m.Height = msg.Height
	case tea.KeyMsg:
		switch msg.String() {
		case "q", "ctrl+c":
			return m, tea.Quit
		case "down", "j":
			if m.SelectedIndex < len(m.Snapshot.Statuses)-1 {
				m.SelectedIndex++
			}
		case "up", "k":
			if m.SelectedIndex > 0 {
				m.SelectedIndex--
			}
		case "?":
			m.Mode = ModeHelp
		case "esc":
			m.Mode = ModeOverview
		}
	}
	return m, nil
}
```

Create `internal/tui/theme/theme.go`:

```go
package theme

import "charm.land/lipgloss/v2"

type Theme struct {
	Title    lipgloss.Style
	Header   lipgloss.Style
	Selected lipgloss.Style
	Muted    lipgloss.Style
	Panel    lipgloss.Style
}

func Default() Theme {
	return Theme{
		Title:    lipgloss.NewStyle().Bold(true),
		Header:   lipgloss.NewStyle().Bold(true).Foreground(lipgloss.Color("39")),
		Selected: lipgloss.NewStyle().Foreground(lipgloss.Color("205")).Bold(true),
		Muted:    lipgloss.NewStyle().Foreground(lipgloss.Color("244")),
		Panel:    lipgloss.NewStyle().Padding(0, 1),
	}
}
```

Create `internal/tui/controltower/view.go`:

```go
package controltower

import (
	"fmt"
	"path/filepath"
	"strings"

	"charm.land/lipgloss/v2"

	"github.com/thisguymartin/grove/internal/tui/theme"
)

func (m Model) View() string {
	t := theme.Default()
	if m.Mode == ModeHelp {
		return t.Title.Render("Grove Help") + "\n\n" + strings.Join([]string{
			"j/k move",
			"enter preview action",
			"p pattern",
			"esc back",
			"q quit",
		}, "\n")
	}

	width := m.Width
	if width <= 0 {
		width = 100
	}
	columnWidth := (width - 6) / 3
	if columnWidth < 24 {
		columnWidth = 24
	}

	title := fmt.Sprintf("Grove Control Tower    repo: %s  base: %s", filepath.Base(string(m.Snapshot.Root)), m.Snapshot.Base)
	body := lipgloss.JoinHorizontal(
		lipgloss.Top,
		t.Panel.Width(columnWidth).Render(m.renderWorktrees(t)),
		t.Panel.Width(columnWidth).Render(m.renderActions(t)),
		t.Panel.Width(columnWidth).Render(m.renderDetails(t)),
	)
	footer := t.Muted.Render("j/k move  enter act  p pattern  ? help  q quit")

	return t.Title.Render(title) + "\n\n" + body + "\n\n" + footer
}

func (m Model) renderWorktrees(t theme.Theme) string {
	lines := []string{t.Header.Render("Worktrees")}
	for i, status := range m.Snapshot.Statuses {
		prefix := " "
		style := lipgloss.NewStyle()
		if i == m.SelectedIndex {
			prefix = ">"
			style = t.Selected
		}
		line := fmt.Sprintf("%s %s", prefix, status.Worktree.DisplayName())
		lines = append(lines, style.Render(line))
	}
	return strings.Join(lines, "\n")
}

func (m Model) renderActions(t theme.Theme) string {
	lines := []string{t.Header.Render("Needs Action")}
	for i, action := range m.Snapshot.NextActions {
		lines = append(lines, fmt.Sprintf("%d. %s: %s", i+1, action.Branch, action.Label))
	}
	if len(m.Snapshot.NextActions) == 0 {
		lines = append(lines, t.Muted.Render("no actions"))
	}
	return strings.Join(lines, "\n")
}

func (m Model) renderDetails(t theme.Theme) string {
	lines := []string{t.Header.Render("Details")}
	if len(m.Snapshot.Statuses) == 0 {
		return strings.Join(append(lines, t.Muted.Render("no worktrees")), "\n")
	}
	index := m.SelectedIndex
	if index < 0 || index >= len(m.Snapshot.Statuses) {
		index = 0
	}
	status := m.Snapshot.Statuses[index]
	lines = append(lines,
		"Branch: "+status.Worktree.DisplayName(),
		fmt.Sprintf("Dirty: %d", status.DirtyFiles),
		fmt.Sprintf("Ahead/behind: %d/%d", status.Ahead, status.Behind),
		"Checks: "+string(status.Checks),
	)
	return strings.Join(lines, "\n")
}
```

- [ ] **Step 5: Wire `grove tui`**

Modify `cmd/grove/main.go`:

- For `tui`, build `app.Service` with real adapters.
- Load snapshot with `Status(ctx, ".")`.
- Run `tea.NewProgram(controltower.NewModel(snapshot), tea.WithAltScreen()).Run()`.
- Return `1` and print error if snapshot load or program run fails.

- [ ] **Step 6: Verify**

Run:

```bash
go test ./internal/tui/controltower ./cmd/grove
go test ./...
go run ./cmd/grove tui
```

Manual expected TUI behavior:

```text
screen opens with Grove Control Tower, worktree list, needs-action queue, details panel, and q quits cleanly
```

- [ ] **Commit boundary**

Commit:

```bash
git add go.mod go.sum cmd/grove internal/tui
git commit -m "feat: add bubble tea control tower" \
  -m "Introduce the first read-only Grove TUI on top of the Go status snapshot." \
  -m "- Adds Charm Bubble Tea, Bubbles, Lip Gloss, Huh, Glamour, and Log dependencies." \
  -m "- Adds a three-column Control Tower view for worktrees, next actions, and details." \
  -m "- Wires grove tui without replacing existing Bash/Zellij launch behavior."
```

---

## Task 7: Add Pattern Docs And Glamour Viewer

**Purpose:** Make the design patterns visible in the app and editable in one place.

**Files:**

- Create `internal/docs/patterns/adapter.md`
- Create `internal/docs/patterns/command.md`
- Create `internal/docs/patterns/mediator.md`
- Create `internal/docs/patterns/strategy.md`
- Create `internal/docs/patterns/patterns.go`
- Create `internal/tui/components/pattern_viewer.go`
- Create `internal/tui/components/pattern_viewer_test.go`
- Modify `internal/tui/controltower/update.go`
- Modify `internal/tui/controltower/view.go`

- [ ] **Step 1: Add pattern docs**

Create `internal/docs/patterns/adapter.md`:

```markdown
# Adapter

Grove uses Adapter around external tools: git, gh, zellij, and local process inspection.

Edit point:

- `internal/adapters/git`
- `internal/adapters/github`
- `internal/adapters/zellij`
- `internal/adapters/process`

Rule: adapters translate external command output into domain values. Domain packages never shell out.
```

Create `internal/docs/patterns/command.md`:

```markdown
# Command

Grove uses Command for user-triggered operations like open diff, sync branch, create PR, and go to tab.

Edit point:

- `internal/app/actions.go`

Rule: actions expose `Preview` and `Run`, so the TUI can show what will happen before it happens.
```

Create `internal/docs/patterns/mediator.md`:

```markdown
# Mediator

Grove uses Mediator in the Control Tower model.

Edit point:

- `internal/tui/controltower`

Rule: the model coordinates component messages and mode changes. Components render focused pieces of state.
```

Create `internal/docs/patterns/strategy.md`:

```markdown
# Strategy

Grove uses Strategy for next-action scoring.

Edit point:

- `internal/domain/workspace/status.go`

Rule: scoring decides priority. Rendering decides how that priority looks.
```

- [ ] **Step 2: Embed pattern docs**

Create `internal/docs/patterns/patterns.go`:

```go
package patterns

import "embed"

//go:embed adapter.md command.md mediator.md strategy.md
var files embed.FS

func ByName(name string) string {
	content, err := files.ReadFile(name + ".md")
	if err != nil {
		return "# Pattern\n\nPattern documentation is unavailable."
	}
	return string(content)
}
```

- [ ] **Step 3: Create failing viewer tests**

Create `internal/tui/components/pattern_viewer_test.go`:

```go
package components

import (
	"strings"
	"testing"
)

func TestPatternViewerRendersMarkdown(t *testing.T) {
	viewer := NewPatternViewer()

	out, err := viewer.Render("# Adapter\n\nGrove wraps git.")
	if err != nil {
		t.Fatalf("Render returned error: %v", err)
	}
	if !strings.Contains(out, "Adapter") || !strings.Contains(out, "Grove wraps git") {
		t.Fatalf("rendered output missing markdown content:\n%s", out)
	}
}
```

- [ ] **Step 4: Implement Glamour renderer**

Create `internal/tui/components/pattern_viewer.go`:

```go
package components

import "github.com/charmbracelet/glamour"

type PatternViewer struct {
	width int
}

func NewPatternViewer() PatternViewer {
	return PatternViewer{width: 88}
}

func (v PatternViewer) Render(markdown string) (string, error) {
	renderer, err := glamour.NewTermRenderer(
		glamour.WithAutoStyle(),
		glamour.WithWordWrap(v.width),
	)
	if err != nil {
		return "", err
	}
	return renderer.Render(markdown)
}
```

- [ ] **Step 5: Wire `p` key to pattern mode**

Modify `internal/tui/controltower/model.go`:

```go
type Model struct {
	Snapshot        workspace.Workspace
	SelectedIndex   int
	Width           int
	Height          int
	Mode            Mode
	PatternMarkdown string
}
```

Modify `internal/tui/controltower/update.go`:

```go
import "github.com/thisguymartin/grove/internal/docs/patterns"

// inside the tea.KeyMsg switch:
case "p":
	m.Mode = ModePattern
	m.PatternMarkdown = patterns.ByName("strategy")
case "esc":
	m.Mode = ModeOverview
```

Modify `internal/tui/controltower/view.go`:

```go
import "github.com/thisguymartin/grove/internal/tui/components"

// inside View before the overview render path:
if m.Mode == ModePattern {
	viewer := components.NewPatternViewer()
	rendered, err := viewer.Render(m.PatternMarkdown)
	if err != nil {
		rendered = m.PatternMarkdown
	}
	return rendered + "\n" + theme.Default().Muted.Render("esc back  q quit")
}
```

- [ ] **Step 6: Verify**

Run:

```bash
go test ./internal/tui/components ./internal/tui/controltower
go test ./...
```

Manual expected TUI behavior:

```text
pressing p shows a rendered pattern explanation; esc returns to the Control Tower
```

- [ ] **Commit boundary**

Commit:

```bash
git add internal/docs/patterns internal/tui/components internal/tui/controltower
git commit -m "docs: add pattern guide inside the tui" \
  -m "Document Grove's core design patterns where future edits will happen." \
  -m "- Adds markdown docs for Adapter, Command, Mediator, and Strategy." \
  -m "- Adds a Glamour-backed pattern viewer for the Control Tower." \
  -m "- Wires the pattern view into the TUI with the p key."
```

---

## Task 8: Add Action Command Lifecycle And Huh Confirmations

**Purpose:** Let the TUI preview and run safe actions while guarding destructive actions.

**Files:**

- Create `internal/app/actions.go`
- Create `internal/app/actions_test.go`
- Create `internal/tui/forms/new_worktree.go`
- Create `internal/tui/forms/sync_branch.go`
- Create `internal/tui/forms/create_pr.go`
- Modify `internal/tui/controltower/messages.go`
- Modify `internal/tui/controltower/update.go`
- Modify `internal/tui/controltower/view.go`

- [ ] **Step 1: Create failing action tests**

Create `internal/app/actions_test.go`:

```go
package app

import (
	"context"
	"strings"
	"testing"
)

func TestActionPreviewDescribesCommand(t *testing.T) {
	action := ShellAction{
		Name: "open diff",
		Cwd:  "/repo/grove",
		Args: []string{"git", "diff"},
	}

	preview := action.Preview()
	if !strings.Contains(preview, "git diff") || !strings.Contains(preview, "/repo/grove") {
		t.Fatalf("Preview = %q, want command and cwd", preview)
	}
}

func TestActionRunUsesRunner(t *testing.T) {
	runner := recordingRunner{}
	action := ShellAction{
		Name:   "open diff",
		Cwd:    "/repo/grove",
		Args:   []string{"git", "diff"},
		Runner: &runner,
	}

	if err := action.Run(context.Background()); err != nil {
		t.Fatalf("Run returned error: %v", err)
	}
	if runner.cwd != "/repo/grove" || strings.Join(runner.args, " ") != "git diff" {
		t.Fatalf("runner got cwd=%q args=%v", runner.cwd, runner.args)
	}
}
```

- [ ] **Step 2: Implement command pattern**

Create `internal/app/actions.go`:

```go
package app

import (
	"context"
	"fmt"
	"strings"
)

type Action interface {
	Preview() string
	Run(context.Context) error
}

type ActionRunner interface {
	RunInDir(context.Context, string, ...string) error
}

type ShellAction struct {
	Name   string
	Cwd    string
	Args   []string
	Runner ActionRunner
}

func (a ShellAction) Preview() string {
	return fmt.Sprintf("%s\ncwd: %s\ncmd: %s", a.Name, a.Cwd, strings.Join(a.Args, " "))
}

func (a ShellAction) Run(ctx context.Context) error {
	if a.Runner == nil {
		return fmt.Errorf("runner is required for action %q", a.Name)
	}
	return a.Runner.RunInDir(ctx, a.Cwd, a.Args...)
}
```

- [ ] **Step 3: Add Huh forms**

Create `internal/tui/forms/new_worktree.go`:

```go
package forms

import huh "charm.land/huh/v2"

type NewWorktreeValues struct {
	Branch string
	Base   string
}

func NewWorktreeForm(values *NewWorktreeValues) *huh.Form {
	return huh.NewForm(
		huh.NewGroup(
			huh.NewInput().Title("Branch").Value(&values.Branch),
			huh.NewInput().Title("Base").Value(&values.Base),
		),
	)
}
```

Create `internal/tui/forms/sync_branch.go`:

```go
package forms

import huh "charm.land/huh/v2"

type SyncBranchValues struct {
	Branch  string
	Confirm bool
}

func SyncBranchForm(values *SyncBranchValues) *huh.Form {
	return huh.NewForm(
		huh.NewGroup(
			huh.NewConfirm().Title("Sync "+values.Branch+" with base?").Value(&values.Confirm),
		),
	)
}
```

Create `internal/tui/forms/create_pr.go`:

```go
package forms

import huh "charm.land/huh/v2"

type CreatePRValues struct {
	Branch string
	Title  string
	Draft  bool
}

func CreatePRForm(values *CreatePRValues) *huh.Form {
	return huh.NewForm(
		huh.NewGroup(
			huh.NewInput().Title("Title").Value(&values.Title),
			huh.NewConfirm().Title("Create as draft?").Value(&values.Draft),
		),
	)
}
```

`rm` is intentionally not wired in this task.

- [ ] **Step 4: Wire safe keys**

Modify `internal/tui/controltower/model.go`:

```go
const (
	ModeOverview Mode = iota
	ModeHelp
	ModePattern
	ModeAction
	ModeForm
)

type Model struct {
	Snapshot        workspace.Workspace
	SelectedIndex   int
	Width           int
	Height          int
	Mode            Mode
	PatternMarkdown string
	ActionPreview   string
	Form            tea.Model
}
```

Modify `internal/tui/controltower/update.go`:

```go
import groveforms "github.com/thisguymartin/grove/internal/tui/forms"

// inside the tea.KeyMsg switch:
case "enter":
	m.Mode = ModeAction
	m.ActionPreview = m.previewSelectedAction()
case "g":
	m.Mode = ModeAction
	m.ActionPreview = "go to tab: " + m.selectedBranch()
case "a":
	m.Mode = ModeAction
	m.ActionPreview = "open agent for: " + m.selectedBranch()
case "n":
	values := &groveforms.NewWorktreeValues{Base: string(m.Snapshot.Base)}
	m.Form = groveforms.NewWorktreeForm(values)
	m.Mode = ModeForm
case "s":
	values := &groveforms.SyncBranchValues{Branch: m.selectedBranch()}
	m.Form = groveforms.SyncBranchForm(values)
	m.Mode = ModeForm
case "c":
	values := &groveforms.CreatePRValues{Branch: m.selectedBranch(), Title: m.selectedBranch()}
	m.Form = groveforms.CreatePRForm(values)
	m.Mode = ModeForm
case "esc":
	m.Mode = ModeOverview
	m.Form = nil
```

Add helper methods in `internal/tui/controltower/model.go`:

```go
func (m Model) selectedBranch() string {
	if len(m.Snapshot.Statuses) == 0 {
		return ""
	}
	index := m.SelectedIndex
	if index < 0 || index >= len(m.Snapshot.Statuses) {
		index = 0
	}
	return m.Snapshot.Statuses[index].Worktree.DisplayName()
}

func (m Model) previewSelectedAction() string {
	branch := m.selectedBranch()
	for _, action := range m.Snapshot.NextActions {
		if string(action.Branch) == branch {
			return action.Label + ": " + branch
		}
	}
	return "no action: " + branch
}
```

Modify `internal/tui/controltower/view.go`:

```go
if m.Mode == ModeAction {
	return theme.Default().Title.Render("Action Preview") + "\n\n" + m.ActionPreview + "\n\n" + theme.Default().Muted.Render("esc back  q quit")
}
if m.Mode == ModeForm && m.Form != nil {
	return m.Form.View()
}
```

- [ ] **Step 5: Verify**

Run:

```bash
go test ./internal/app ./internal/tui/forms ./internal/tui/controltower
go test ./...
```

Manual expected TUI behavior:

```text
enter shows an action preview; n/s/c open forms; escape returns to overview without running a destructive command
```

- [ ] **Commit boundary**

Commit:

```bash
git add internal/app internal/tui/forms internal/tui/controltower
git commit -m "feat: add guarded tui action lifecycle" \
  -m "Introduce Command-pattern actions so Grove can preview operations before running them." \
  -m "- Adds action previews and runner boundaries in the app layer." \
  -m "- Adds Huh forms for new worktree, sync, and create PR flows." \
  -m "- Keeps destructive operations behind explicit confirmations."
```

---

## Task 9: Add Zellij Layout Builder Compatibility

**Purpose:** Preserve Grove's existing launch behavior while moving layout construction into Go.

**Files:**

- Create `internal/domain/session/zellij.go`
- Create `internal/adapters/zellij/layout.go`
- Create `internal/adapters/zellij/layout_test.go`
- Create `internal/adapters/zellij/client.go`
- Modify `cmd/grove/main.go`

- [ ] **Step 1: Create failing layout builder test**

Create `internal/adapters/zellij/layout_test.go`:

```go
package zellij

import (
	"strings"
	"testing"

	"github.com/thisguymartin/grove/internal/domain/workspace"
)

func TestBuildLayoutIncludesOverviewAndWorktreeTabs(t *testing.T) {
	layout := BuildLayout(LayoutInput{
		SessionName: "grove",
		AIEditor:   "codex",
		Workspace: workspace.Workspace{
			Root: "/repo/grove",
			Worktrees: []workspace.Worktree{
				{Path: "/repo/grove", Branch: "main"},
				{Path: "/repo/.worktrees/feat-go-tui", Branch: "feat/go-tui"},
			},
		},
	})

	for _, want := range []string{
		`tab name="Overview"`,
		`tab name="main"`,
		`tab name="feat/go-tui"`,
		`cwd "/repo/.worktrees/feat-go-tui"`,
		`codex`,
	} {
		if !strings.Contains(layout, want) {
			t.Fatalf("layout missing %q:\n%s", want, layout)
		}
	}
}
```

- [ ] **Step 2: Add domain session type**

Create `internal/domain/session/zellij.go`:

```go
package session

type ZellijSession struct {
	Name    string   `json:"name"`
	Running bool    `json:"running"`
	Tabs    []string `json:"tabs"`
}
```

- [ ] **Step 3: Implement layout builder**

Create `internal/adapters/zellij/layout.go`:

```go
package zellij

import (
	"fmt"
	"strings"

	"github.com/thisguymartin/grove/internal/domain/workspace"
)

type LayoutInput struct {
	SessionName string
	AIEditor   string
	Workspace  workspace.Workspace
}

func BuildLayout(input LayoutInput) string {
	var b strings.Builder
	b.WriteString("layout {\n")
	b.WriteString(`  tab name="Overview" {` + "\n")
	b.WriteString(`    pane command="go" { args "run" "./cmd/grove" "tui" }` + "\n")
	b.WriteString("  }\n")
	for _, wt := range input.Workspace.Worktrees {
		name := wt.DisplayName()
		fmt.Fprintf(&b, "  tab name=%q {\n", name)
		fmt.Fprintf(&b, "    pane cwd %q command=\"lazygit\"\n", string(wt.Path))
		if input.AIEditor != "" {
			fmt.Fprintf(&b, "    pane cwd %q command=%q\n", string(wt.Path), input.AIEditor)
		}
		b.WriteString("  }\n")
	}
	b.WriteString("}\n")
	return b.String()
}
```

Match the exact KDL shape expected by current `layouts/workspace.kdl.template`. If the string form above differs from current valid KDL, adjust the builder and test to the existing template syntax before committing.

- [ ] **Step 4: Add Zellij client**

Create `internal/adapters/zellij/client.go` with:

- `Launch(ctx, layoutPath string) error`
- `ListSessions(ctx) ([]session.ZellijSession, error)`
- Runner injection matching the Git adapter.
- Missing `zellij` returns a typed error that CLI can print cleanly.

- [ ] **Step 5: Wire dry-run launch**

Modify `cmd/grove/main.go`:

- Add `grove up --dry-run`.
- It loads workspace status, builds KDL, writes KDL to stdout, and exits 0.
- Do not replace `launch-grove.sh` in this task.

- [ ] **Step 6: Verify**

Run:

```bash
go test ./internal/adapters/zellij ./cmd/grove
go test ./...
go run ./cmd/grove up --dry-run
```

Expected output:

```text
layout {
  tab name="Overview" {
...
```

- [ ] **Commit boundary**

Commit:

```bash
git add internal/domain/session internal/adapters/zellij cmd/grove
git commit -m "feat: build zellij layout from go" \
  -m "Move Grove's layout planning into a tested Go builder while keeping Bash launch compatibility." \
  -m "- Adds a Zellij session domain type and adapter boundary." \
  -m "- Adds a dry-run launch path that prints generated KDL without starting Zellij." \
  -m "- Preserves the current shell launch path until the Go launcher is fully covered."
```

---

## Task 10: Wire Worktree Commands For Scriptability

**Purpose:** Keep terminal-first workflows fast outside the TUI.

**Files:**

- Modify `cmd/grove/main.go`
- Modify `cmd/grove/main_test.go`
- Modify `internal/app/service.go`
- Modify `internal/app/actions.go`

- [ ] **Step 1: Add CLI tests for line-oriented commands**

Extend `cmd/grove/main_test.go` to cover:

- `grove ls` prints one worktree per line: branch, status, path.
- `grove root` prints repo root.
- `grove which` prints current worktree branch.
- `grove run <branch> -- <cmd>` returns the runner exit code.

Use injected services/runners in tests so no test shells out accidentally.

- [ ] **Step 2: Implement scriptable commands**

Modify dispatcher:

- `ls`: line-oriented worktree list.
- `root`: repo root.
- `which`: branch for current path.
- `run <branch> -- <cmd>`: resolve worktree by branch, run command in that cwd, preserve exit code.
- `status --json`: keep existing JSON behavior.
- `tui`: keep full-screen mode.

- [ ] **Step 3: Verify**

Run:

```bash
go test ./cmd/grove ./internal/app
go test ./...
go run ./cmd/grove ls
go run ./cmd/grove root
go run ./cmd/grove which
```

Expected:

```text
ls/root/which produce line-oriented output with no TUI escape sequences
```

- [ ] **Commit boundary**

Commit:

```bash
git add cmd/grove internal/app
git commit -m "feat: add scriptable worktree commands" \
  -m "Bring the most common Grove shell habits into the Go CLI without requiring the TUI." \
  -m "- Adds ls, root, which, and run command routes." \
  -m "- Preserves machine-friendly stdout and command exit codes." \
  -m "- Keeps status JSON and TUI paths on the same service layer."
```

---

## Task 11: Add Docs And Migration Notes

**Purpose:** Make the new path understandable and keep the migration state explicit.

**Files:**

- Modify `README.md`
- Modify `docs/commands.md`
- Modify `docs/architecture.md`
- Create `docs/go-control-tower.md`

- [ ] **Step 1: Document current architecture**

Create `docs/go-control-tower.md` with:

```markdown
# Go Control Tower

Grove is migrating from shell-first orchestration to a Go CLI with a Bubble Tea Control Tower.

Current flow:

```text
CLI args -> app.Service -> domain workspace snapshot -> adapters -> CLI output or TUI model
```

Compatibility flow:

```text
launch-grove.sh -> launch-worktrees.sh -> generated Zellij KDL
```

The Go path is experimental until installer wiring prefers the compiled binary.

## Edit Points

- Command routing: `cmd/grove`
- Use cases: `internal/app`
- Worktree rules: `internal/domain/workspace`
- External tools: `internal/adapters`
- TUI coordination: `internal/tui/controltower`
- Pattern docs: `internal/docs/patterns`
```

- [ ] **Step 2: Update existing docs**

Modify:

- `README.md`: add a short "Experimental Go CLI" section with `go run ./cmd/grove status --json` and `go run ./cmd/grove tui`.
- `docs/commands.md`: mark Go-backed commands and Bash-backed commands.
- `docs/architecture.md`: add the Go flow beside the existing Bash/Zellij flow.

- [ ] **Step 3: Verify docs references**

Run:

```bash
rg -n "go run ./cmd/grove|Go Control Tower|internal/tui/controltower" README.md docs
go test ./...
```

Expected:

```text
docs contain the new commands and all tests still pass
```

- [ ] **Commit boundary**

Commit:

```bash
git add README.md docs/commands.md docs/architecture.md docs/go-control-tower.md
git commit -m "docs: explain go control tower migration" \
  -m "Document the experimental Go CLI path and how it coexists with the existing Bash launcher." \
  -m "- Adds edit-point guidance for the domain, adapter, app, and TUI packages." \
  -m "- Updates command and architecture docs with the current migration state."
```

---

## Task 12: Final Verification And Local Handoff

**Purpose:** Confirm the first migration slice works from tests, CLI, and manual TUI launch.

**Files:**

- No new files expected.
- Edit only if verification exposes a real issue.

- [ ] **Step 1: Run full checks**

Run:

```bash
go test ./...
go vet ./...
go run ./cmd/grove version
go run ./cmd/grove status --json
go run ./cmd/grove ls
go run ./cmd/grove up --dry-run
```

Expected:

```text
all tests pass; vet is clean; CLI commands exit 0 in the Grove repo
```

- [ ] **Step 2: Manual TUI smoke test**

Run:

```bash
go run ./cmd/grove tui
```

Check:

- Title reads `Grove Control Tower`.
- Worktrees list is visible.
- Needs Action list is visible.
- Details panel changes when pressing `j`/`k`.
- `p` opens the pattern view.
- `esc` returns from pattern/help/form modes.
- `q` exits without terminal corruption.

- [ ] **Step 3: Inspect git state**

Run:

```bash
git status --short
git log --oneline -5
```

Expected:

```text
only intentional files are modified; recent commits match the task boundaries
```

- [ ] **Step 4: Capture residual risks**

If any known issue remains, add it to `docs/go-control-tower.md` under `## Known Gaps` with:

- Exact command that fails.
- Exact error.
- What code path owns the fix.

- [ ] **Commit boundary if docs changed**

Commit only if Step 4 changed docs:

```bash
git add docs/go-control-tower.md
git commit -m "docs: capture go control tower gaps" \
  -m "Record verified migration gaps discovered during final local checks." \
  -m "- Lists exact commands, errors, and owning code paths for follow-up work."
```

## Completion Criteria

- `go test ./...` passes.
- `go vet ./...` passes.
- `go run ./cmd/grove status --json` emits a valid workspace snapshot.
- `go run ./cmd/grove tui` opens and exits cleanly.
- Existing Bash launch scripts are still present and unmodified unless a task explicitly changed docs around them.
- Pattern docs exist and are reachable from the TUI.
- README and architecture docs describe the migration state.

## Source Ledger

- Local design spec: `docs/superpowers/specs/2026-06-08-go-control-tower-design.md`
- Local command docs: `docs/commands.md`
- Local architecture docs: `docs/architecture.md`
- Charm v2 docs checked on June 8, 2026:
  - `https://charm.land/blog/v2/`
  - `https://charm.land/libs/`
  - `https://github.com/charmbracelet/bubbles`
  - `https://github.com/charmbracelet/huh`
  - `https://github.com/charmbracelet/glow`
  - `https://superfile.dev/`

Confidence: 85%. The repo/domain split is grounded in the current Grove files and committed design spec. Exact Charm import APIs should be confirmed with `go doc` and `go test` immediately after `go get` in Task 6.
