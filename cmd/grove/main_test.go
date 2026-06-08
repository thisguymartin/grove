package main

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"strings"
	"testing"

	"github.com/thisguymartin/grove/internal/domain/workspace"
)

type fakeStatusService struct {
	snapshot workspace.Workspace
	err      error
	called   bool
	path     string
}

func (f *fakeStatusService) Status(_ context.Context, path string) (workspace.Workspace, error) {
	f.called = true
	f.path = path
	if f.err != nil {
		return workspace.Workspace{}, f.err
	}
	return f.snapshot, nil
}

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

func TestRunPlaceholderCommandsReportNotWired(t *testing.T) {
	for _, cmd := range []string{"status", "ls", "tui"} {
		t.Run(cmd, func(t *testing.T) {
			var stdout bytes.Buffer
			var stderr bytes.Buffer

			code := run(context.Background(), []string{cmd}, &stdout, &stderr)
			if code != 2 {
				t.Fatalf("%s exit code = %d, want 2", cmd, code)
			}
			if !strings.Contains(stderr.String(), cmd+" is not wired yet") {
				t.Fatalf("stderr missing not-wired message:\n%s", stderr.String())
			}
			if stdout.Len() != 0 {
				t.Fatalf("stdout = %q, want empty", stdout.String())
			}
		})
	}
}

func TestRunStatusJSONPrintsSnapshot(t *testing.T) {
	var stdout bytes.Buffer
	var stderr bytes.Buffer
	svc := &fakeStatusService{
		snapshot: workspace.Workspace{
			Root: "/fake/repo",
			Base: "main",
			Worktrees: []workspace.Worktree{
				{Path: "/fake/repo", Branch: "main", Head: "abc"},
				{Path: "/fake/repo/.worktrees/feat-with-pr", Branch: "feat/with-pr", Head: "def"},
			},
			Statuses: []workspace.WorktreeStatus{
				{
					Worktree: workspace.Worktree{Path: "/fake/repo", Branch: "main", Head: "abc"},
					Clean:    true,
					HasPR:    true,
					Checks:   workspace.CheckStateUnknown,
				},
				{
					Worktree: workspace.Worktree{Path: "/fake/repo/.worktrees/feat-with-pr", Branch: "feat/with-pr", Head: "def"},
					Clean:    true,
					HasPR:    true,
					Checks:   workspace.CheckStateUnknown,
				},
			},
			NextActions: []workspace.NextAction{
				{Branch: "main", Kind: workspace.NextActionIdle, Label: "idle", Score: 0},
				{Branch: "feat/with-pr", Kind: workspace.NextActionIdle, Label: "idle", Score: 0},
			},
		},
	}
	originalNewStatusService := newStatusService
	newStatusService = func() statusService {
		return svc
	}
	t.Cleanup(func() {
		newStatusService = originalNewStatusService
	})

	code := run(context.Background(), []string{"status", "--json"}, &stdout, &stderr)
	if code != 0 {
		t.Fatalf("status --json exit code = %d, want 0; stderr=%q", code, stderr.String())
	}

	output := stdout.Bytes()
	var snapshot workspace.Workspace
	if err := json.NewDecoder(bytes.NewReader(output)).Decode(&snapshot); err != nil {
		t.Fatalf("status --json output is not workspace JSON: %v\n%s", err, string(output))
	}
	if !svc.called {
		t.Fatal("status service was not called")
	}
	if svc.path != "." {
		t.Fatalf("status service path = %q, want .", svc.path)
	}
	if snapshot.Root != "/fake/repo" {
		t.Fatalf("Root = %q, want /fake/repo", snapshot.Root)
	}
	if len(snapshot.Statuses) != 2 {
		t.Fatalf("len(Statuses) = %d, want 2", len(snapshot.Statuses))
	}
	if !snapshot.Statuses[1].HasPR {
		t.Fatalf("feature status HasPR = false, want true: %#v", snapshot.Statuses[1])
	}
	if len(snapshot.NextActions) != 2 {
		t.Fatalf("len(NextActions) = %d, want 2", len(snapshot.NextActions))
	}
	if snapshot.NextActions[1].Branch != "feat/with-pr" || snapshot.NextActions[1].Kind != workspace.NextActionIdle {
		t.Fatalf("feature next action = %#v, want injected idle action", snapshot.NextActions[1])
	}
}

func TestRunStatusJSONReturnsErrorWhenServiceFails(t *testing.T) {
	var stdout bytes.Buffer
	var stderr bytes.Buffer
	svc := &fakeStatusService{err: errors.New("load status failed")}
	originalNewStatusService := newStatusService
	newStatusService = func() statusService {
		return svc
	}
	t.Cleanup(func() {
		newStatusService = originalNewStatusService
	})

	code := run(context.Background(), []string{"status", "--json"}, &stdout, &stderr)
	if code != 1 {
		t.Fatalf("status --json exit code = %d, want 1", code)
	}
	if stdout.Len() != 0 {
		t.Fatalf("stdout = %q, want empty", stdout.String())
	}
	if !strings.Contains(stderr.String(), "load status failed") {
		t.Fatalf("stderr missing service error:\n%s", stderr.String())
	}
}

func TestRunStatusUnsupportedFlagsExitTwo(t *testing.T) {
	var stdout bytes.Buffer
	var stderr bytes.Buffer

	code := run(context.Background(), []string{"status", "--porcelain"}, &stdout, &stderr)
	if code != 2 {
		t.Fatalf("status unsupported flag exit code = %d, want 2", code)
	}
	if !strings.Contains(stderr.String(), "unsupported status flags") {
		t.Fatalf("stderr missing unsupported status flags:\n%s", stderr.String())
	}
	if stdout.Len() != 0 {
		t.Fatalf("stdout = %q, want empty", stdout.String())
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
