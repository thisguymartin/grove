package git

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"os/exec"
	"strings"
	"time"

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
		if isOriginHeadCommand(name, args) && isMissingOriginHeadStderr(cmdErr.Stderr) {
			return nil, MissingOriginHeadError{Err: cmdErr}
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

type MissingOriginHeadError struct {
	Err error
}

func (e MissingOriginHeadError) Error() string {
	if e.Err == nil {
		return "missing origin HEAD"
	}
	return fmt.Sprintf("missing origin HEAD: %v", e.Err)
}

func (e MissingOriginHeadError) Unwrap() error {
	return e.Err
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

func (c *Client) Root(ctx context.Context, path string) (workspace.RepoRoot, error) {
	out, err := c.runner.Run(ctx, "git", "-C", path, "rev-parse", "--show-toplevel")
	if err != nil {
		return "", err
	}
	return workspace.RepoRoot(strings.TrimSpace(string(out))), nil
}

func (c *Client) BaseBranch(ctx context.Context, root workspace.RepoRoot) (workspace.BranchName, error) {
	out, err := c.runner.Run(ctx, "git", "-C", string(root), "symbolic-ref", "--short", "refs/remotes/origin/HEAD")
	if err != nil {
		if isMissingOriginHeadError(err) {
			return "main", nil
		}
		return "", err
	}

	branch := strings.TrimSpace(strings.TrimPrefix(string(out), "origin/"))
	if branch == "" {
		return "main", nil
	}
	return workspace.BranchName(branch), nil
}

func isMissingOriginHeadError(err error) bool {
	var missing MissingOriginHeadError
	if errors.As(err, &missing) {
		return true
	}

	var missingPtr *MissingOriginHeadError
	return errors.As(err, &missingPtr)
}

func isOriginHeadCommand(name string, args []string) bool {
	return name == "git" &&
		len(args) == 5 &&
		args[0] == "-C" &&
		args[2] == "symbolic-ref" &&
		args[3] == "--short" &&
		args[4] == "refs/remotes/origin/HEAD"
}

func isMissingOriginHeadStderr(stderr string) bool {
	stderr = strings.ToLower(stderr)
	return strings.Contains(stderr, "refs/remotes/origin/head") &&
		(strings.Contains(stderr, "not a symbolic ref") ||
			strings.Contains(stderr, "no such ref"))
}

func (c *Client) Worktrees(ctx context.Context, root workspace.RepoRoot) ([]workspace.Worktree, error) {
	out, err := c.runner.Run(ctx, "git", "-C", string(root), "worktree", "list", "--porcelain")
	if err != nil {
		return nil, err
	}
	return ParseWorktreePorcelain(string(out))
}
