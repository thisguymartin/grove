package github

import (
	"context"
	"errors"
	"os/exec"
	"reflect"
	"strings"
	"testing"
	"time"

	"github.com/thisguymartin/grove/internal/domain/review"
)

func TestClientPullRequestsMapsGHJSON(t *testing.T) {
	runner := &fakeRunner{
		output: map[string]string{
			"/repo/grove | gh pr list --state all --limit 100 --json number,url,state,isDraft,headRefName,statusCheckRollup": `[
				{"number":17,"url":"https://github.com/thisguymartin/grove/pull/17","state":"OPEN","isDraft":false,"headRefName":"feat/go-control-tower","statusCheckRollup":[{"name":"test","status":"COMPLETED","conclusion":"SUCCESS"}]},
				{"number":18,"url":"https://github.com/thisguymartin/grove/pull/18","state":"MERGED","isDraft":true,"headRefName":"feat/agent-status","statusCheckRollup":[{"name":"lint","state":"FAILURE"}]}
			]`,
		},
	}
	client := NewClient(runner)

	got, err := client.PullRequests(context.Background(), "/repo/grove")
	if err != nil {
		t.Fatalf("PullRequests returned error: %v", err)
	}

	want := []review.PullRequest{
		{Branch: "feat/go-control-tower", Number: 17, URL: "https://github.com/thisguymartin/grove/pull/17", State: "OPEN", Draft: false, Checks: "passing", CheckDetails: []string{"test: success"}},
		{Branch: "feat/agent-status", Number: 18, URL: "https://github.com/thisguymartin/grove/pull/18", State: "MERGED", Draft: true, Checks: "failed", CheckDetails: []string{"lint: failure"}},
	}
	if len(got) != len(want) {
		t.Fatalf("len(PullRequests) = %d, want %d; got=%#v", len(got), len(want), got)
	}
	for i := range want {
		if !reflect.DeepEqual(got[i], want[i]) {
			t.Fatalf("PullRequests[%d] = %#v, want %#v", i, got[i], want[i])
		}
	}
	assertCalled(t, runner, "/repo/grove", "gh pr list --state all --limit 100 --json number,url,state,isDraft,headRefName,statusCheckRollup")
}

func TestClientPullRequestsMissingGHReturnsUnavailable(t *testing.T) {
	runner := &fakeRunner{
		err: map[string]error{
			"/repo/grove | gh pr list --state all --limit 100 --json number,url,state,isDraft,headRefName,statusCheckRollup": exec.ErrNotFound,
		},
	}
	client := NewClient(runner)

	got, err := client.PullRequests(context.Background(), "/repo/grove")
	if len(got) != 0 {
		t.Fatalf("PullRequests = %#v, want empty slice", got)
	}
	var unavailable UnavailableError
	if !errors.As(err, &unavailable) {
		t.Fatalf("PullRequests error = %v, want UnavailableError", err)
	}
	if unavailable.Tool != "gh" {
		t.Fatalf("UnavailableError.Tool = %q, want gh", unavailable.Tool)
	}
}

func TestClientPullRequestsGenericNoSuchFileErrorIsCommandError(t *testing.T) {
	wantErr := errors.New("open .git/config: no such file or directory")
	runner := &fakeRunner{
		err: map[string]error{
			"/repo/grove | gh pr list --state all --limit 100 --json number,url,state,isDraft,headRefName,statusCheckRollup": wantErr,
		},
	}
	client := NewClient(runner)

	got, err := client.PullRequests(context.Background(), "/repo/grove")
	if len(got) != 0 {
		t.Fatalf("PullRequests = %#v, want empty slice", got)
	}
	var unavailable UnavailableError
	if errors.As(err, &unavailable) {
		t.Fatalf("PullRequests error = %v, did not want UnavailableError", err)
	}
	if !errors.Is(err, wantErr) {
		t.Fatalf("PullRequests error = %v, want wrapping %v", err, wantErr)
	}
	if !strings.Contains(err.Error(), "gh pr list") {
		t.Fatalf("PullRequests error = %q, want command context", err.Error())
	}
}

func TestClientPullRequestsInvalidJSONWrapsContext(t *testing.T) {
	runner := &fakeRunner{
		output: map[string]string{
			"/repo/grove | gh pr list --state all --limit 100 --json number,url,state,isDraft,headRefName,statusCheckRollup": "{",
		},
	}
	client := NewClient(runner)

	_, err := client.PullRequests(context.Background(), "/repo/grove")
	if err == nil {
		t.Fatal("PullRequests returned nil error, want JSON error")
	}
	if !strings.Contains(err.Error(), "gh pr list json") {
		t.Fatalf("PullRequests error = %q, want JSON context", err.Error())
	}
}

func TestExecRunnerHonorsConfiguredTimeout(t *testing.T) {
	_, err := (ExecRunner{Timeout: 20 * time.Millisecond}).Run(context.Background(), "", "sh", "-c", "sleep 1")
	if !errors.Is(err, context.DeadlineExceeded) {
		t.Fatalf("Run error = %v, want context deadline exceeded", err)
	}
}

func TestDefaultTimeoutIsFiveSeconds(t *testing.T) {
	if defaultTimeout != 5*time.Second {
		t.Fatalf("default timeout = %s", defaultTimeout)
	}
}

type fakeRunner struct {
	output map[string]string
	err    map[string]error
	calls  []fakeCall
}

type fakeCall struct {
	cwd     string
	command string
}

func (f *fakeRunner) Run(_ context.Context, cwd string, name string, args ...string) ([]byte, error) {
	parts := append([]string{name}, args...)
	command := strings.Join(parts, " ")
	key := cwd + " | " + command
	f.calls = append(f.calls, fakeCall{cwd: cwd, command: command})

	if err, ok := f.err[key]; ok {
		return nil, err
	}
	out, ok := f.output[key]
	if !ok {
		return nil, errors.New("missing fake output for " + key)
	}
	return []byte(out), nil
}

func assertCalled(t *testing.T, runner *fakeRunner, wantCWD string, wantCommand string) {
	t.Helper()

	for _, call := range runner.calls {
		if call.cwd == wantCWD && call.command == wantCommand {
			return
		}
	}
	t.Fatalf("calls = %#v, want cwd %q command %q", runner.calls, wantCWD, wantCommand)
}
