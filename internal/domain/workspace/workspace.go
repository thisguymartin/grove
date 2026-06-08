package workspace

type RepoRoot string

type Workspace struct {
	Root        RepoRoot         `json:"root"`
	Base        BranchName       `json:"base"`
	Worktrees   []Worktree       `json:"worktrees"`
	Statuses    []WorktreeStatus `json:"statuses"`
	NextActions []NextAction     `json:"next_actions"`
}
