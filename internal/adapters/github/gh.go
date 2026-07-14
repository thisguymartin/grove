package github

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"os/exec"
	"strings"
	"time"

	"github.com/thisguymartin/grove/internal/domain/review"
	"github.com/thisguymartin/grove/internal/domain/workspace"
)

type Runner interface {
	Run(ctx context.Context, cwd string, name string, args ...string) ([]byte, error)
}

const defaultTimeout = 5 * time.Second

type ExecRunner struct {
	Timeout time.Duration
}

func (r ExecRunner) Run(ctx context.Context, cwd string, name string, args ...string) ([]byte, error) {
	timeout := r.Timeout
	if timeout <= 0 {
		timeout = defaultTimeout
	}
	ctx, cancel := context.WithTimeout(ctx, timeout)
	defer cancel()

	cmd := exec.CommandContext(ctx, name, args...)
	if cwd != "" {
		cmd.Dir = cwd
	}
	var stderr bytes.Buffer
	cmd.Stderr = &stderr

	out, err := cmd.Output()
	if err != nil {
		cmdErr := commandError{
			Name:   name,
			Args:   append([]string(nil), args...),
			Err:    err,
			Stderr: strings.TrimSpace(stderr.String()),
		}
		if ctxErr := ctx.Err(); ctxErr != nil {
			cmdErr.Err = ctxErr
		}
		return nil, cmdErr
	}
	return out, nil
}

type commandError struct {
	Name   string
	Args   []string
	Err    error
	Stderr string
}

func (e commandError) Error() string {
	command := strings.TrimSpace(e.Name + " " + strings.Join(e.Args, " "))
	if e.Stderr == "" {
		return fmt.Sprintf("%s: %v", command, e.Err)
	}
	return fmt.Sprintf("%s: %v: %s", command, e.Err, e.Stderr)
}

func (e commandError) Unwrap() error {
	return e.Err
}

type UnavailableError struct {
	Tool string
}

func (e UnavailableError) Error() string {
	if e.Tool == "" {
		return "optional tool unavailable"
	}
	return e.Tool + " unavailable"
}

func (e UnavailableError) OptionalToolUnavailable() bool {
	return true
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

func (c *Client) PullRequests(ctx context.Context, root workspace.RepoRoot) ([]review.PullRequest, error) {
	out, err := c.runner.Run(ctx, string(root), "gh", "pr", "list", "--state", "all", "--limit", "100", "--json", "number,url,state,isDraft,headRefName,statusCheckRollup")
	if err != nil {
		if isMissingExecutable(err) {
			return []review.PullRequest{}, UnavailableError{Tool: "gh"}
		}
		return nil, fmt.Errorf("gh pr list: %w", err)
	}

	var rows []struct {
		Number            int    `json:"number"`
		URL               string `json:"url"`
		State             string `json:"state"`
		IsDraft           bool   `json:"isDraft"`
		HeadRefName       string `json:"headRefName"`
		StatusCheckRollup []struct {
			Name       string `json:"name"`
			Status     string `json:"status"`
			Conclusion string `json:"conclusion"`
			State      string `json:"state"`
		} `json:"statusCheckRollup"`
	}
	if err := json.Unmarshal(out, &rows); err != nil {
		return nil, fmt.Errorf("gh pr list json: %w", err)
	}

	prs := make([]review.PullRequest, 0, len(rows))
	for _, row := range rows {
		checks, details := summarizeChecks(row.StatusCheckRollup)
		prs = append(prs, review.PullRequest{
			Branch:       row.HeadRefName,
			Number:       row.Number,
			URL:          row.URL,
			State:        row.State,
			Draft:        row.IsDraft,
			Checks:       checks,
			CheckDetails: details,
		})
	}
	return prs, nil
}

func summarizeChecks(rows []struct {
	Name       string `json:"name"`
	Status     string `json:"status"`
	Conclusion string `json:"conclusion"`
	State      string `json:"state"`
}) (string, []string) {
	if len(rows) == 0 {
		return string(workspace.CheckStateUnknown), nil
	}
	state := workspace.CheckStatePassing
	details := make([]string, 0, len(rows))
	for _, row := range rows {
		status := strings.ToUpper(row.Status)
		conclusion := strings.ToUpper(row.Conclusion)
		legacyState := strings.ToUpper(row.State)
		detail := row.Name
		if detail == "" {
			detail = "check"
		}
		if conclusion != "" {
			detail += ": " + strings.ToLower(conclusion)
		} else if legacyState != "" {
			detail += ": " + strings.ToLower(legacyState)
		} else {
			detail += ": " + strings.ToLower(status)
		}
		details = append(details, detail)
		switch {
		case legacyState == "FAILURE" || legacyState == "ERROR":
			state = workspace.CheckStateFailed
		case legacyState == "PENDING" || legacyState == "EXPECTED":
			if state != workspace.CheckStateFailed {
				state = workspace.CheckStatePending
			}
		case conclusion == "FAILURE" || conclusion == "CANCELLED" || conclusion == "TIMED_OUT" || conclusion == "ACTION_REQUIRED" || conclusion == "STALE" || conclusion == "STARTUP_FAILURE":
			state = workspace.CheckStateFailed
		case state != workspace.CheckStateFailed && legacyState == "" && (status != "COMPLETED" || conclusion == ""):
			state = workspace.CheckStatePending
		}
	}
	return string(state), details
}

func isMissingExecutable(err error) bool {
	if errors.Is(err, exec.ErrNotFound) {
		return true
	}

	var execErr *exec.Error
	if errors.As(err, &execErr) && errors.Is(execErr.Err, exec.ErrNotFound) {
		return true
	}

	return false
}
