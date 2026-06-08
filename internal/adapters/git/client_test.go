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
