package zellij

import (
	"context"
	"errors"
	"strings"
	"testing"
	"time"

	"github.com/thisguymartin/grove/internal/domain/workspace"
)

type fakeRunner struct {
	output map[string]string
	errors map[string]error
}

func (f fakeRunner) Run(_ context.Context, name string, args ...string) ([]byte, error) {
	key := strings.Join(append([]string{name}, args...), " ")
	if err := f.errors[key]; err != nil {
		return nil, err
	}
	out, ok := f.output[key]
	if !ok {
		return nil, errors.New("missing fake output for " + key)
	}
	return []byte(out), nil
}

func TestSessionsIgnoreAStaleSessionWhenAnotherCanBeInspected(t *testing.T) {
	client := NewClient(fakeRunner{
		output: map[string]string{
			"zellij list-sessions --short --no-formatting":   "stale\nlive\n",
			"zellij --session live action list-panes --json": `[]`,
		},
		errors: map[string]error{"zellij --session stale action list-panes --json": errors.New("no active session")},
	})
	got, err := client.Sessions(context.Background(), "/repo", nil)
	if err != nil || len(got) != 0 {
		t.Fatalf("Sessions = %#v, error=%v", got, err)
	}
}

func TestSessionsOnlyReturnsRepositoryPanes(t *testing.T) {
	client := NewClient(fakeRunner{output: map[string]string{
		"zellij list-sessions --short --no-formatting": "grove-one\nother\n",
		"zellij --session grove-one action list-panes --json": `[
			{"id":1,"pane_command":"codex","pane_cwd":"/repo/grove/.worktrees/feat-one","tab_name":"feat-one"},
			{"id":2,"pane_command":"zsh","pane_cwd":"/tmp","tab_name":"elsewhere"}
		]`,
		"zellij --session other action list-panes --json": `[]`,
	}})

	got, err := client.Sessions(context.Background(), "/repo/grove", []workspace.Worktree{
		{Path: "/repo/grove", Branch: "main"},
		{Path: "/repo/grove/.worktrees/feat-one", Branch: "feat/one"},
	})
	if err != nil {
		t.Fatalf("Sessions returned error: %v", err)
	}
	if len(got) != 1 || got[0].Branch != "feat/one" || got[0].Editor != "codex" || got[0].PaneID != 1 {
		t.Fatalf("Sessions = %#v", got)
	}
}

func TestExecRunnerHonorsConfiguredTimeout(t *testing.T) {
	_, err := (ExecRunner{Timeout: 20 * time.Millisecond}).Run(context.Background(), "sh", "-c", "sleep 1")
	if !errors.Is(err, context.DeadlineExceeded) {
		t.Fatalf("Run error = %v, want context deadline exceeded", err)
	}
}

func TestDefaultTimeoutIsTwoSeconds(t *testing.T) {
	if defaultTimeout != 2*time.Second {
		t.Fatalf("default timeout = %s", defaultTimeout)
	}
}
