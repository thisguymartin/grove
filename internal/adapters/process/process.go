package process

import (
	"bytes"
	"context"
	"fmt"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	"github.com/thisguymartin/grove/internal/domain/agent"
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

type Client struct {
	runner Runner
}

func NewClient(runner Runner) *Client {
	if runner == nil {
		runner = ExecRunner{}
	}
	return &Client{runner: runner}
}

func (c *Client) Sessions(ctx context.Context) ([]agent.Session, error) {
	out, err := c.runner.Run(ctx, "ps", "-axo", "pid=,command=")
	if err != nil {
		return nil, fmt.Errorf("ps -axo pid=,command=: %w", err)
	}
	return parseSessions(string(out)), nil
}

func parseSessions(output string) []agent.Session {
	sessions := []agent.Session{}
	for _, line := range strings.Split(output, "\n") {
		session, ok := parseSessionLine(line)
		if ok {
			sessions = append(sessions, session)
		}
	}
	return sessions
}

func parseSessionLine(line string) (agent.Session, bool) {
	line = strings.TrimSpace(line)
	if line == "" {
		return agent.Session{}, false
	}

	fields := strings.Fields(line)
	if len(fields) < 2 {
		return agent.Session{}, false
	}

	pid, err := strconv.Atoi(fields[0])
	if err != nil {
		return agent.Session{}, false
	}

	command := strings.TrimSpace(strings.TrimPrefix(line, fields[0]))
	editor, ok := detectEditor(command)
	if !ok {
		return agent.Session{}, false
	}

	return agent.Session{
		Editor:  editor,
		PID:     pid,
		Command: command,
	}, true
}

func detectEditor(command string) (string, bool) {
	fields := strings.Fields(command)
	if len(fields) == 0 {
		return "", false
	}

	executable := strings.ToLower(filepath.Base(fields[0]))
	for _, editor := range []string{"claude", "gemini", "opencode", "codex"} {
		if executable == editor {
			return editor, true
		}
	}
	return "", false
}
