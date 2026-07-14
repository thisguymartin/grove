package git

import (
	"context"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/thisguymartin/grove/internal/domain/workspace"
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

func TestClientBaseBranchUsesOriginHead(t *testing.T) {
	runner := &fakeRunner{
		output: map[string]string{
			"git -C /repo/grove symbolic-ref --short refs/remotes/origin/HEAD": "origin/main\n",
		},
	}
	client := NewClient(runner)

	got, err := client.BaseBranch(context.Background(), "/repo/grove")
	if err != nil {
		t.Fatalf("BaseBranch returned error: %v", err)
	}
	if got != "main" {
		t.Fatalf("BaseBranch = %q, want main", got)
	}
}

func TestClientBaseBranchFallsBackWhenOriginHeadMissing(t *testing.T) {
	runner := &fakeRunner{
		err: map[string]error{
			"git -C /repo/grove symbolic-ref --short refs/remotes/origin/HEAD": MissingOriginHeadError{Err: errors.New("origin HEAD is not set")},
		},
	}
	client := NewClient(runner)

	got, err := client.BaseBranch(context.Background(), "/repo/grove")
	if err != nil {
		t.Fatalf("BaseBranch returned error: %v", err)
	}
	if got != "main" {
		t.Fatalf("BaseBranch = %q, want main", got)
	}
}

func TestClientBaseBranchFallsBackOnEmptyOriginHead(t *testing.T) {
	runner := &fakeRunner{
		output: map[string]string{
			"git -C /repo/grove symbolic-ref --short refs/remotes/origin/HEAD": "\n",
		},
	}
	client := NewClient(runner)

	got, err := client.BaseBranch(context.Background(), "/repo/grove")
	if err != nil {
		t.Fatalf("BaseBranch returned error: %v", err)
	}
	if got != "main" {
		t.Fatalf("BaseBranch = %q, want main", got)
	}
}

func TestClientBaseBranchPropagatesUnexpectedError(t *testing.T) {
	wantErr := errors.New("permission denied")
	runner := &fakeRunner{
		err: map[string]error{
			"git -C /repo/grove symbolic-ref --short refs/remotes/origin/HEAD": wantErr,
		},
	}
	client := NewClient(runner)

	got, err := client.BaseBranch(context.Background(), "/repo/grove")
	if err == nil {
		t.Fatal("BaseBranch returned nil error, want permission denied")
	}
	if got != "" {
		t.Fatalf("BaseBranch = %q, want empty branch on error", got)
	}
	if !errors.Is(err, wantErr) {
		t.Fatalf("BaseBranch error = %v, want wrapping %v", err, wantErr)
	}
}

func TestClientBaseBranchPropagatesContextCancellation(t *testing.T) {
	runner := &fakeRunner{
		err: map[string]error{
			"git -C /repo/grove symbolic-ref --short refs/remotes/origin/HEAD": context.Canceled,
		},
	}
	client := NewClient(runner)

	got, err := client.BaseBranch(context.Background(), "/repo/grove")
	if err == nil {
		t.Fatal("BaseBranch returned nil error, want context.Canceled")
	}
	if got != "" {
		t.Fatalf("BaseBranch = %q, want empty branch on error", got)
	}
	if !errors.Is(err, context.Canceled) {
		t.Fatalf("BaseBranch error = %v, want context.Canceled", err)
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

func TestClientWorktreesPropagatesParserError(t *testing.T) {
	runner := &fakeRunner{
		output: map[string]string{
			"git -C /repo/grove worktree list --porcelain": "HEAD abc\n",
		},
	}
	client := NewClient(runner)

	_, err := client.Worktrees(context.Background(), "/repo/grove")
	if err == nil {
		t.Fatal("Worktrees returned nil error, want parser error")
	}
	if !strings.Contains(err.Error(), "HEAD before worktree") {
		t.Fatalf("Worktrees error = %q, want parser context", err.Error())
	}
}

func TestClientInspectLoadsDirtyCountsUpstreamCountsAndMergedState(t *testing.T) {
	runner := &fakeRunner{output: map[string]string{
		"git -C /repo/grove branch --merged main --format=%(refname:short)":  "main\nfeat/done\n",
		"git -C /repo/grove status --porcelain":                              "",
		"git -C /repo/dirty status --porcelain":                              " M one.go\n?? two.go\n",
		"git -C /repo/grove rev-list --left-right --count main...feat/dirty": "3\t2\n",
		"git -C /repo/done status --porcelain":                               "",
		"git -C /repo/grove rev-list --left-right --count main...feat/done":  "0\t1\n",
	}}
	client := NewClient(runner)

	got, err := client.Inspect(context.Background(), "/repo/grove", "main", []workspace.Worktree{
		{Path: "/repo/grove", Branch: "main"},
		{Path: "/repo/dirty", Branch: "feat/dirty"},
		{Path: "/repo/done", Branch: "feat/done"},
	})
	if err != nil {
		t.Fatalf("Inspect returned error: %v", err)
	}
	if status := got["/repo/dirty"]; status.DirtyFiles != 2 || status.Behind != 3 || status.Ahead != 2 || status.Merged {
		t.Fatalf("dirty status = %#v", status)
	}
	if status := got["/repo/done"]; !status.Merged || status.Ahead != 1 {
		t.Fatalf("done status = %#v", status)
	}
}

func TestExecRunnerHonorsConfiguredTimeout(t *testing.T) {
	_, err := (ExecRunner{Timeout: 20 * time.Millisecond}).Run(context.Background(), "sh", "-c", "sleep 1")
	if !errors.Is(err, context.DeadlineExceeded) {
		t.Fatalf("Run error = %v, want context deadline exceeded", err)
	}
}

func TestDefaultTimeoutIsThreeSeconds(t *testing.T) {
	if defaultTimeout != 3*time.Second {
		t.Fatalf("default timeout = %s", defaultTimeout)
	}
}

func TestExecRunnerReturnsStdoutOnly(t *testing.T) {
	dir := t.TempDir()
	script := filepath.Join(dir, "write-streams")
	if err := os.WriteFile(script, []byte("#!/bin/sh\nprintf stdout\nprintf stderr >&2\n"), 0o755); err != nil {
		t.Fatalf("write script: %v", err)
	}

	got, err := ExecRunner{}.Run(context.Background(), script)
	if err != nil {
		t.Fatalf("Run returned error: %v", err)
	}
	if string(got) != "stdout" {
		t.Fatalf("Run output = %q, want stdout", got)
	}
}

type fakeRunner struct {
	output map[string]string
	err    map[string]error
	calls  []string
}

func (f *fakeRunner) Run(_ context.Context, name string, args ...string) ([]byte, error) {
	parts := append([]string{name}, args...)
	key := strings.Join(parts, " ")
	f.calls = append(f.calls, key)

	if err, ok := f.err[key]; ok {
		return nil, err
	}
	out, ok := f.output[key]
	if !ok {
		return nil, fmt.Errorf("missing fake output for %s", key)
	}
	return []byte(out), nil
}
