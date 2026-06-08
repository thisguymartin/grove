package workspace

import "sort"

type CheckState string

const (
	CheckStateUnknown CheckState = "unknown"
	CheckStatePassing CheckState = "passing"
	CheckStatePending CheckState = "pending"
	CheckStateFailed  CheckState = "failed"
)

type NextActionKind string

const (
	NextActionOpenChecks NextActionKind = "open_checks"
	NextActionOpenDiff   NextActionKind = "open_diff"
	NextActionSync       NextActionKind = "sync"
	NextActionCreatePR   NextActionKind = "create_pr"
	NextActionIdle       NextActionKind = "idle"
)

type WorktreeStatus struct {
	Worktree   Worktree   `json:"worktree"`
	Clean      bool       `json:"clean"`
	DirtyFiles int        `json:"dirty_files"`
	Ahead      int        `json:"ahead"`
	Behind     int        `json:"behind"`
	HasPR      bool       `json:"has_pr"`
	Checks     CheckState `json:"checks"`
}

type NextAction struct {
	Branch BranchName     `json:"branch"`
	Kind   NextActionKind `json:"kind"`
	Label  string         `json:"label"`
	Score  int            `json:"score"`
}

func ScoreNextActions(statuses []WorktreeStatus) []NextAction {
	out := make([]NextAction, 0, len(statuses))
	for _, status := range statuses {
		out = append(out, scoreStatus(status))
	}
	sort.SliceStable(out, func(i, j int) bool {
		return out[i].Score > out[j].Score
	})
	return out
}

func scoreStatus(status WorktreeStatus) NextAction {
	branch := status.Worktree.Branch
	switch {
	case status.Checks == CheckStateFailed:
		return NextAction{Branch: branch, Kind: NextActionOpenChecks, Label: "open failed checks", Score: 500}
	case status.DirtyFiles > 0:
		return NextAction{Branch: branch, Kind: NextActionOpenDiff, Label: "review dirty files", Score: 400}
	case status.Behind > 0:
		return NextAction{Branch: branch, Kind: NextActionSync, Label: "sync with base", Score: 300}
	case branch != "main" && branch != "" && !status.HasPR:
		return NextAction{Branch: branch, Kind: NextActionCreatePR, Label: "create pull request", Score: 200}
	default:
		return NextAction{Branch: branch, Kind: NextActionIdle, Label: "idle", Score: 0}
	}
}
