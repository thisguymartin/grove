package workspace

import "testing"

func TestScoreNextActionPriority(t *testing.T) {
	input := []WorktreeStatus{
		{Worktree: Worktree{Branch: "docs/spec"}, DirtyFiles: 2},
		{Worktree: Worktree{Branch: "fix/install"}, Checks: CheckStateFailed},
		{Worktree: Worktree{Branch: "feat/go-tui"}, Behind: 3},
		{Worktree: Worktree{Branch: "main"}, Clean: true, HasPR: true},
	}

	got := ScoreNextActions(input)
	if len(got) != 4 {
		t.Fatalf("len(actions) = %d, want 4", len(got))
	}
	if got[0].Branch != "fix/install" || got[0].Kind != NextActionOpenChecks {
		t.Fatalf("first action = %#v, want fix/install open checks", got[0])
	}
	if got[1].Branch != "docs/spec" || got[1].Kind != NextActionOpenDiff {
		t.Fatalf("second action = %#v, want docs/spec open diff", got[1])
	}
	if got[2].Branch != "feat/go-tui" || got[2].Kind != NextActionSync {
		t.Fatalf("third action = %#v, want feat/go-tui sync", got[2])
	}
	if got[3].Kind != NextActionIdle {
		t.Fatalf("last action = %#v, want idle", got[3])
	}
}

func TestScoreNextActionCreatePRUsesHasPRState(t *testing.T) {
	tests := []struct {
		name   string
		branch BranchName
	}{
		{name: "base named branch", branch: "main"},
		{name: "empty branch", branch: ""},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := ScoreNextActions([]WorktreeStatus{
				{Worktree: Worktree{Branch: tt.branch}, Clean: true, HasPR: false},
			})

			if len(got) != 1 {
				t.Fatalf("len(actions) = %d, want 1", len(got))
			}
			if got[0].Kind != NextActionCreatePR {
				t.Fatalf("action = %#v, want create PR", got[0])
			}
		})
	}
}
