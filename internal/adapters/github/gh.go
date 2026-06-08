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
	Run(context.Context, string, ...string) ([]byte, error)
}

type ExecRunner struct{}

func (ExecRunner) Run(ctx context.Context, name string, args ...string) ([]byte, error) {
	ctx, cancel := context.WithTimeout(ctx, 10*time.Second)
	defer cancel()

	cmd := exec.CommandContext(ctx, name, args...)
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
	_ = root

	out, err := c.runner.Run(ctx, "gh", "pr", "list", "--json", "number,url,state,isDraft,headRefName")
	if err != nil {
		if isMissingExecutable(err) {
			return []review.PullRequest{}, UnavailableError{Tool: "gh"}
		}
		return nil, fmt.Errorf("gh pr list: %w", err)
	}

	var rows []struct {
		Number      int    `json:"number"`
		URL         string `json:"url"`
		State       string `json:"state"`
		IsDraft     bool   `json:"isDraft"`
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
			Draft:  row.IsDraft,
		})
	}
	return prs, nil
}

func isMissingExecutable(err error) bool {
	if errors.Is(err, exec.ErrNotFound) {
		return true
	}

	var execErr *exec.Error
	if errors.As(err, &execErr) && errors.Is(execErr.Err, exec.ErrNotFound) {
		return true
	}

	var cmdErr commandError
	if errors.As(err, &cmdErr) {
		return hasMissingExecutableMessage(cmdErr.Err)
	}

	return hasMissingExecutableMessage(err)
}

func hasMissingExecutableMessage(err error) bool {
	if err == nil {
		return false
	}
	message := strings.ToLower(err.Error())
	return strings.Contains(message, "executable file not found") ||
		strings.Contains(message, "no such file or directory")
}
