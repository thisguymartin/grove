package workspace

type BranchName string
type WorktreePath string

type Worktree struct {
	Path   WorktreePath `json:"path"`
	Branch BranchName   `json:"branch"`
	Head   string       `json:"head"`
	Bare   bool         `json:"bare"`
	Locked bool         `json:"locked"`
}

func (w Worktree) DisplayName() string {
	if w.Bare {
		return "bare"
	}
	if w.Branch != "" {
		return string(w.Branch)
	}
	return "detached@" + shortSHA(w.Head)
}

func shortSHA(value string) string {
	if len(value) <= 7 {
		return value
	}
	return value[:7]
}
