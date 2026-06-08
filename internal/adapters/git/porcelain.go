package git

import (
	"bufio"
	"fmt"
	"strings"

	"github.com/thisguymartin/grove/internal/domain/workspace"
)

func ParseWorktreePorcelain(input string) ([]workspace.Worktree, error) {
	var out []workspace.Worktree
	current := workspace.Worktree{}
	recordLine := 0

	flush := func() error {
		if current.Path == "" {
			return nil
		}
		if current.Head == "" {
			return fmt.Errorf("line %d: missing HEAD", recordLine)
		}
		out = append(out, current)
		current = workspace.Worktree{}
		recordLine = 0
		return nil
	}

	scanner := bufio.NewScanner(strings.NewReader(input))
	lineNumber := 0
	for scanner.Scan() {
		lineNumber++
		line := scanner.Text()
		if line == "" {
			if err := flush(); err != nil {
				return nil, err
			}
			continue
		}

		key, value, _ := strings.Cut(line, " ")
		switch key {
		case "worktree":
			if value == "" {
				return nil, fmt.Errorf("line %d: worktree requires a value", lineNumber)
			}
			if err := flush(); err != nil {
				return nil, err
			}
			current.Path = workspace.WorktreePath(value)
			recordLine = lineNumber
		case "HEAD":
			if value == "" {
				return nil, fmt.Errorf("line %d: HEAD requires a value", lineNumber)
			}
			current.Head = value
		case "branch":
			if value == "" {
				return nil, fmt.Errorf("line %d: branch requires a value", lineNumber)
			}
			current.Branch = workspace.BranchName(strings.TrimPrefix(value, "refs/heads/"))
		case "detached":
			current.Branch = ""
		case "locked":
			current.Locked = true
		}
	}
	if err := scanner.Err(); err != nil {
		return nil, err
	}
	if err := flush(); err != nil {
		return nil, err
	}

	return out, nil
}
