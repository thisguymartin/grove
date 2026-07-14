package main

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"strings"
	"testing"
	"time"

	"github.com/thisguymartin/grove/internal/domain/workspace"
)

type fakeStatusService struct {
	snapshot workspace.Workspace
	err      error
	path     string
}

func (f *fakeStatusService) Status(_ context.Context, path string) (workspace.Workspace, error) {
	f.path = path
	return f.snapshot, f.err
}

func TestRunStatusSupportsCompactFullAndJSONWithFlexiblePathOrdering(t *testing.T) {
	tests := []struct {
		name     string
		args     []string
		wantPath string
		wantText string
		wantJSON bool
	}{
		{name: "compact", args: []string{"status"}, wantPath: ".", wantText: "BRANCH"},
		{name: "full before path", args: []string{"status", "--full", "/repo"}, wantPath: "/repo", wantText: "Integrations"},
		{name: "full after path", args: []string{"status", "/repo", "--full"}, wantPath: "/repo", wantText: "Integrations"},
		{name: "json", args: []string{"status", "/repo", "--json"}, wantPath: "/repo", wantJSON: true},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			svc := &fakeStatusService{snapshot: sampleSnapshot()}
			useService(t, svc)
			var stdout, stderr bytes.Buffer
			code := run(context.Background(), tt.args, &stdout, &stderr)
			if code != 0 {
				t.Fatalf("exit code = %d; stderr=%q", code, stderr.String())
			}
			if svc.path != tt.wantPath {
				t.Fatalf("path = %q, want %q", svc.path, tt.wantPath)
			}
			if tt.wantJSON {
				var got workspace.Workspace
				if err := json.Unmarshal(stdout.Bytes(), &got); err != nil || got.SchemaVersion != 1 {
					t.Fatalf("JSON output = %q, error=%v", stdout.String(), err)
				}
			} else if !strings.Contains(stdout.String(), tt.wantText) {
				t.Fatalf("output missing %q:\n%s", tt.wantText, stdout.String())
			}
		})
	}
}

func TestRunStatusInvalidCombinationsExitTwo(t *testing.T) {
	for _, args := range [][]string{
		{"status", "--full", "--json"},
		{"status", "one", "two"},
		{"status", "--porcelain"},
	} {
		var stdout, stderr bytes.Buffer
		if code := run(context.Background(), args, &stdout, &stderr); code != 2 {
			t.Fatalf("args=%v exit code=%d, want 2", args, code)
		}
		if stdout.Len() != 0 || stderr.Len() == 0 {
			t.Fatalf("args=%v stdout=%q stderr=%q", args, stdout.String(), stderr.String())
		}
	}
}

func TestRunStatusServiceFailureExitsOne(t *testing.T) {
	svc := &fakeStatusService{err: errors.New("not a git repository")}
	useService(t, svc)
	var stdout, stderr bytes.Buffer
	if code := run(context.Background(), []string{"status"}, &stdout, &stderr); code != 1 {
		t.Fatalf("exit code = %d", code)
	}
	if !strings.Contains(stderr.String(), "not a git repository") {
		t.Fatalf("stderr = %q", stderr.String())
	}
}

func TestRunHelpOnlyAdvertisesThinStatusCLI(t *testing.T) {
	var stdout, stderr bytes.Buffer
	if code := run(context.Background(), []string{"help"}, &stdout, &stderr); code != 0 {
		t.Fatalf("exit code = %d", code)
	}
	for _, want := range []string{"grove status [path] [--full | --json]", "grove version"} {
		if !strings.Contains(stdout.String(), want) {
			t.Fatalf("help missing %q:\n%s", want, stdout.String())
		}
	}
	for _, unwanted := range []string{"grove tui", "grove ls"} {
		if strings.Contains(stdout.String(), unwanted) {
			t.Fatalf("help contains %q:\n%s", unwanted, stdout.String())
		}
	}
}

func TestRunUnknownCommandReportsError(t *testing.T) {
	var stdout, stderr bytes.Buffer
	if code := run(context.Background(), []string{"wat"}, &stdout, &stderr); code != 2 {
		t.Fatalf("exit code = %d", code)
	}
	if !strings.Contains(stderr.String(), `unknown command "wat"`) {
		t.Fatalf("stderr = %q", stderr.String())
	}
}

func useService(t *testing.T, svc statusService) {
	t.Helper()
	original := newStatusService
	newStatusService = func() statusService { return svc }
	t.Cleanup(func() { newStatusService = original })
}

func sampleSnapshot() workspace.Workspace {
	statuses := []workspace.WorktreeStatus{{Worktree: workspace.Worktree{Path: "/repo", Branch: "main"}, Clean: true, PRKnown: true, Checks: workspace.CheckStateUnknown}}
	return workspace.Workspace{
		SchemaVersion: 1,
		GeneratedAt:   time.Date(2026, 7, 14, 12, 0, 0, 0, time.UTC),
		Repository:    workspace.Repository{Root: "/repo", Base: "main"},
		Integrations: workspace.Integrations{
			Git: workspace.IntegrationHealth{State: workspace.IntegrationAvailable},
		},
		Statuses: statuses, NextActions: workspace.ScoreNextActions(statuses),
	}
}
