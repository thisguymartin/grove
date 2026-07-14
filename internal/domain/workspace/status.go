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
	NextActionRemove     NextActionKind = "remove_worktree"
	NextActionIdle       NextActionKind = "idle"
)

type WorktreeStatus struct {
	Worktree     Worktree   `json:"worktree"`
	Clean        bool       `json:"clean"`
	DirtyFiles   int        `json:"dirty_files"`
	Ahead        int        `json:"ahead"`
	Behind       int        `json:"behind"`
	Merged       bool       `json:"merged"`
	PRKnown      bool       `json:"pr_known"`
	PREligible   bool       `json:"pr_eligible"`
	HasPR        bool       `json:"has_pr"`
	PRNumber     int        `json:"pr_number,omitempty"`
	PRURL        string     `json:"pr_url,omitempty"`
	PRState      string     `json:"pr_state,omitempty"`
	Checks       CheckState `json:"checks"`
	CheckDetails []string   `json:"check_details,omitempty"`
	Agent        string     `json:"agent,omitempty"`
	Panes        []Pane     `json:"panes,omitempty"`
}

type GitStatus struct {
	DirtyFiles int
	Ahead      int
	Behind     int
	Merged     bool
}

type Pane struct {
	Tab     string `json:"tab"`
	PaneID  int    `json:"pane_id"`
	Command string `json:"command"`
	Path    string `json:"path"`
}

type NextAction struct {
	Branch       BranchName     `json:"branch"`
	WorktreePath WorktreePath   `json:"worktree_path"`
	Kind         NextActionKind `json:"kind"`
	Label        string         `json:"label"`
	Score        int            `json:"score"`
}

func ScoreNextActions(statuses []WorktreeStatus) []NextAction {
	type scoredAction struct {
		action NextAction
		path   WorktreePath
	}

	scored := make([]scoredAction, 0, len(statuses))
	for _, status := range statuses {
		action := scoreStatus(status)
		action.WorktreePath = status.Worktree.Path
		scored = append(scored, scoredAction{
			action: action,
			path:   status.Worktree.Path,
		})
	}
	sort.SliceStable(scored, func(i, j int) bool {
		if scored[i].action.Score != scored[j].action.Score {
			return scored[i].action.Score > scored[j].action.Score
		}
		if scored[i].action.Branch != scored[j].action.Branch {
			return scored[i].action.Branch < scored[j].action.Branch
		}
		return scored[i].path < scored[j].path
	})

	out := make([]NextAction, 0, len(scored))
	for _, item := range scored {
		out = append(out, item.action)
	}
	return out
}

func scoreStatus(status WorktreeStatus) NextAction {
	branch := status.Worktree.Branch
	switch {
	case status.Checks == CheckStateFailed:
		return NextAction{Branch: branch, Kind: NextActionOpenChecks, Label: "open failed checks", Score: 500}
	case status.DirtyFiles > 0:
		return NextAction{Branch: branch, Kind: NextActionOpenDiff, Label: "review dirty files", Score: 400}
	case status.Behind > 0 && !status.Merged:
		return NextAction{Branch: branch, Kind: NextActionSync, Label: "sync with base", Score: 300}
	case status.PREligible && !status.HasPR && !status.Merged:
		return NextAction{Branch: branch, Kind: NextActionCreatePR, Label: "create pull request", Score: 200}
	case status.Merged:
		return NextAction{Branch: branch, Kind: NextActionRemove, Label: "remove merged worktree", Score: 100}
	default:
		return NextAction{Branch: branch, Kind: NextActionIdle, Label: "idle", Score: 0}
	}
}
