package workspace

import "time"

type RepoRoot string

type IntegrationState string

const (
	IntegrationAvailable IntegrationState = "available"
	IntegrationUnknown   IntegrationState = "unknown"
)

type IntegrationHealth struct {
	State  IntegrationState `json:"state"`
	Reason string           `json:"reason,omitempty"`
}

type Integrations struct {
	Git    IntegrationHealth `json:"git"`
	GitHub IntegrationHealth `json:"github"`
	Zellij IntegrationHealth `json:"zellij"`
}

type Repository struct {
	Root RepoRoot   `json:"root"`
	Base BranchName `json:"base"`
}

type Workspace struct {
	SchemaVersion int              `json:"schema_version"`
	GeneratedAt   time.Time        `json:"generated_at"`
	Repository    Repository       `json:"repository"`
	Integrations  Integrations     `json:"integrations"`
	Statuses      []WorktreeStatus `json:"worktrees"`
	NextActions   []NextAction     `json:"next_actions"`

	Root      RepoRoot   `json:"-"`
	Base      BranchName `json:"-"`
	Worktrees []Worktree `json:"-"`
}
