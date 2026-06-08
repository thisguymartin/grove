package workspace

type BranchName string
type WorktreePath string

type Worktree struct {
	Path   WorktreePath `json:"path"`
	Branch BranchName   `json:"branch"`
	Head   string       `json:"head"`
	Locked bool         `json:"locked"`
}

func (w Worktree) DisplayName() string {
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
