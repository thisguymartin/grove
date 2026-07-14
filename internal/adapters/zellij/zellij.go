package zellij

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"os/exec"
	"path/filepath"
	"strings"
	"time"

	"github.com/thisguymartin/grove/internal/domain/agent"
	"github.com/thisguymartin/grove/internal/domain/workspace"
)

const defaultTimeout = 2 * time.Second

type Runner interface {
	Run(context.Context, string, ...string) ([]byte, error)
}

type ExecRunner struct {
	Timeout time.Duration
}

func (r ExecRunner) Run(ctx context.Context, name string, args ...string) ([]byte, error) {
	timeout := r.Timeout
	if timeout <= 0 {
		timeout = defaultTimeout
	}
	ctx, cancel := context.WithTimeout(ctx, timeout)
	defer cancel()

	cmd := exec.CommandContext(ctx, name, args...)
	var stderr bytes.Buffer
	cmd.Stderr = &stderr
	out, err := cmd.Output()
	if err == nil {
		return out, nil
	}
	if ctxErr := ctx.Err(); ctxErr != nil {
		err = ctxErr
	}
	return nil, fmt.Errorf("%s %s: %w: %s", name, strings.Join(args, " "), err, strings.TrimSpace(stderr.String()))
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

func (c *Client) Sessions(ctx context.Context, _ workspace.RepoRoot, worktrees []workspace.Worktree) ([]agent.Session, error) {
	out, err := c.runner.Run(ctx, "zellij", "list-sessions", "--short", "--no-formatting")
	if err != nil {
		if isMissingExecutable(err) {
			return nil, fmt.Errorf("zellij unavailable: %w", err)
		}
		if strings.Contains(strings.ToLower(err.Error()), "no active zellij sessions") {
			return []agent.Session{}, nil
		}
		return nil, err
	}

	var sessions []agent.Session
	listedSession := false
	var firstErr error
	for _, line := range strings.Split(string(out), "\n") {
		name := strings.TrimSpace(line)
		if name == "" {
			continue
		}
		paneOut, err := c.runner.Run(ctx, "zellij", "--session", name, "action", "list-panes", "--json")
		if err != nil {
			if firstErr == nil {
				firstErr = fmt.Errorf("list panes for %s: %w", name, err)
			}
			continue
		}
		listedSession = true
		parsed, err := parsePanes(paneOut, worktrees)
		if err != nil {
			return nil, fmt.Errorf("parse panes for %s: %w", name, err)
		}
		sessions = append(sessions, parsed...)
	}
	if !listedSession && firstErr != nil {
		return nil, firstErr
	}
	return sessions, nil
}

func parsePanes(data []byte, worktrees []workspace.Worktree) ([]agent.Session, error) {
	var rows []struct {
		PaneID      int    `json:"id"`
		PaneCommand string `json:"pane_command"`
		PaneCWD     string `json:"pane_cwd"`
		TabName     string `json:"tab_name"`
		Exited      bool   `json:"exited"`
	}
	if err := json.Unmarshal(data, &rows); err != nil {
		return nil, err
	}

	result := make([]agent.Session, 0, len(rows))
	for _, row := range rows {
		if row.Exited {
			continue
		}
		worktree, ok := matchingWorktree(row.PaneCWD, worktrees)
		if !ok {
			continue
		}
		result = append(result, agent.Session{
			Branch:  string(worktree.Branch),
			Editor:  editorName(row.PaneCommand),
			Command: row.PaneCommand,
			Path:    row.PaneCWD,
			Tab:     row.TabName,
			PaneID:  row.PaneID,
		})
	}
	return result, nil
}

func matchingWorktree(cwd string, worktrees []workspace.Worktree) (workspace.Worktree, bool) {
	cleanCWD := filepath.Clean(cwd)
	var match workspace.Worktree
	matchLength := -1
	for _, worktree := range worktrees {
		root := filepath.Clean(string(worktree.Path))
		if (cleanCWD == root || strings.HasPrefix(cleanCWD, root+string(filepath.Separator))) && len(root) > matchLength {
			match = worktree
			matchLength = len(root)
		}
	}
	return match, matchLength >= 0
}

func editorName(command string) string {
	lower := strings.ToLower(command)
	for _, editor := range []string{"codex", "claude", "gemini", "opencode", "aider"} {
		if strings.Contains(lower, editor) {
			return editor
		}
	}
	return ""
}

func isMissingExecutable(err error) bool {
	return errors.Is(err, exec.ErrNotFound) || strings.Contains(strings.ToLower(err.Error()), "executable file not found")
}
