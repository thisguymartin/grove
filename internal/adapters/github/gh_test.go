package github

import (
	"context"
	"errors"
	"os/exec"
	"strings"
	"testing"

	"github.com/thisguymartin/grove/internal/domain/review"
)

func TestClientPullRequestsMapsGHJSON(t *testing.T) {
	runner := &fakeRunner{
		output: map[string]string{
			"gh pr list --json number,url,state,isDraft,headRefName": `[
				{"number":17,"url":"https://github.com/thisguymartin/grove/pull/17","state":"OPEN","isDraft":false,"headRefName":"feat/go-control-tower"},
				{"number":18,"url":"https://github.com/thisguymartin/grove/pull/18","state":"OPEN","isDraft":true,"headRefName":"feat/agent-status"}
			]`,
		},
	}
	client := NewClient(runner)

	got, err := client.PullRequests(context.Background(), "/repo/grove")
	if err != nil {
		t.Fatalf("PullRequests returned error: %v", err)
	}

	want := []review.PullRequest{
		{Branch: "feat/go-control-tower", Number: 17, URL: "https://github.com/thisguymartin/grove/pull/17", State: "OPEN", Draft: false},
		{Branch: "feat/agent-status", Number: 18, URL: "https://github.com/thisguymartin/grove/pull/18", State: "OPEN", Draft: true},
	}
	if len(got) != len(want) {
		t.Fatalf("len(PullRequests) = %d, want %d; got=%#v", len(got), len(want), got)
	}
	for i := range want {
		if got[i] != want[i] {
			t.Fatalf("PullRequests[%d] = %#v, want %#v", i, got[i], want[i])
		}
	}
	assertCalled(t, runner, "gh pr list --json number,url,state,isDraft,headRefName")
}

func TestClientPullRequestsMissingGHReturnsUnavailable(t *testing.T) {
	runner := &fakeRunner{
		err: map[string]error{
			"gh pr list --json number,url,state,isDraft,headRefName": exec.ErrNotFound,
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

func TestClientPullRequestsInvalidJSONWrapsContext(t *testing.T) {
	runner := &fakeRunner{
		output: map[string]string{
			"gh pr list --json number,url,state,isDraft,headRefName": "{",
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
