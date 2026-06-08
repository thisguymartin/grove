package git

import (
	"bufio"
	"strings"

	"github.com/thisguymartin/grove/internal/domain/workspace"
)

func ParseWorktreePorcelain(input string) ([]workspace.Worktree, error) {
	var out []workspace.Worktree
	current := workspace.Worktree{}

	flush := func() {
		if current.Path == "" {
			return
		}
		out = append(out, current)
		current = workspace.Worktree{}
	}

	scanner := bufio.NewScanner(strings.NewReader(input))
	for scanner.Scan() {
		line := scanner.Text()
		if line == "" {
			flush()
			continue
		}

		key, value, _ := strings.Cut(line, " ")
		switch key {
		case "worktree":
			flush()
			current.Path = workspace.WorktreePath(value)
		case "HEAD":
			current.Head = value
		case "branch":
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
	flush()

	return out, nil
}
