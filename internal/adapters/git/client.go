package git

import (
	"context"
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
	out, err := cmd.CombinedOutput()
	if err != nil {
		return nil, fmt.Errorf("%s %s: %w: %s", name, strings.Join(args, " "), err, strings.TrimSpace(string(out)))
	}
	return out, nil
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
	if err == nil {
		branch := strings.TrimSpace(strings.TrimPrefix(string(out), "origin/"))
		if branch != "" {
			return workspace.BranchName(branch), nil
		}
	}
	return "main", nil
}

func (c *Client) Worktrees(ctx context.Context, root workspace.RepoRoot) ([]workspace.Worktree, error) {
	out, err := c.runner.Run(ctx, "git", "-C", string(root), "worktree", "list", "--porcelain")
	if err != nil {
		return nil, err
	}
	return ParseWorktreePorcelain(string(out))
}
