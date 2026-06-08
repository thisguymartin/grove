package process

import (
	"context"
	"errors"
	"strings"
	"testing"

	"github.com/thisguymartin/grove/internal/domain/agent"
)

func TestClientSessionsReturnsEmptyWhenNoKnownAgents(t *testing.T) {
	runner := &fakeRunner{
		output: map[string]string{
			"ps -axo pid=,command=": strings.Join([]string{
				"    1 /sbin/launchd",
				"  222 /usr/bin/ssh-agent",
			}, "\n"),
		},
	}
	client := NewClient(runner)

	got, err := client.Sessions(context.Background())
	if err != nil {
		t.Fatalf("Sessions returned error: %v", err)
	}
	if len(got) != 0 {
		t.Fatalf("Sessions = %#v, want empty slice", got)
	}
	assertCalled(t, runner, "ps -axo pid=,command=")
}

func TestClientSessionsReturnsKnownAgentRows(t *testing.T) {
	runner := &fakeRunner{
		output: map[string]string{
			"ps -axo pid=,command=": strings.Join([]string{
				" 1234 /opt/homebrew/bin/codex --sandbox workspace-write",
				" 5678 claude --dangerously-skip-permissions",
				" 9999 /usr/bin/ssh-agent",
			}, "\n"),
		},
	}
	client := NewClient(runner)

	got, err := client.Sessions(context.Background())
	if err != nil {
		t.Fatalf("Sessions returned error: %v", err)
	}

	want := []agent.Session{
		{PID: 1234, Editor: "codex", Command: "/opt/homebrew/bin/codex --sandbox workspace-write"},
		{PID: 5678, Editor: "claude", Command: "claude --dangerously-skip-permissions"},
	}
	if len(got) != len(want) {
		t.Fatalf("len(Sessions) = %d, want %d; got=%#v", len(got), len(want), got)
	}
	for i := range want {
		if got[i] != want[i] {
			t.Fatalf("Sessions[%d] = %#v, want %#v", i, got[i], want[i])
		}
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
		return nil, errors.New("missing fake output for " + key)
	}
	return []byte(out), nil
}

func assertCalled(t *testing.T, runner *fakeRunner, want string) {
	t.Helper()

	for _, call := range runner.calls {
		if call == want {
			return
		}
	}
	t.Fatalf("calls = %#v, want call %q", runner.calls, want)
}
