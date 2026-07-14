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

func TestScoreNextActionCreatePRRequiresEligibility(t *testing.T) {
	got := ScoreNextActions([]WorktreeStatus{
		{Worktree: Worktree{Branch: "feat/ready"}, Clean: true, Ahead: 2, PRKnown: true, PREligible: true},
		{Worktree: Worktree{Branch: "feat/unknown"}, Clean: true, Ahead: 2},
		{Worktree: Worktree{Branch: "feat/merged"}, Clean: true, Ahead: 2, PRKnown: true, PREligible: true, Merged: true},
	})

	if got[0].Branch != "feat/ready" || got[0].Kind != NextActionCreatePR {
		t.Fatalf("first action = %#v, want eligible branch create PR", got[0])
	}
	if got[1].Branch != "feat/merged" || got[1].Kind != NextActionRemove {
		t.Fatalf("second action = %#v, want merged branch removal", got[1])
	}
	if got[2].Branch != "feat/unknown" || got[2].Kind != NextActionIdle {
		t.Fatalf("third action = %#v, want unknown GitHub state idle", got[2])
	}
}

func TestScoreNextActionsBreaksTiesByBranch(t *testing.T) {
	got := ScoreNextActions([]WorktreeStatus{
		{Worktree: Worktree{Path: "/repo/.worktrees/zeta", Branch: "zeta"}, Clean: true, PREligible: true},
		{Worktree: Worktree{Path: "/repo/.worktrees/alpha", Branch: "alpha"}, Clean: true, PREligible: true},
	})

	if len(got) != 2 {
		t.Fatalf("len(actions) = %d, want 2", len(got))
	}
	if got[0].Branch != "alpha" || got[1].Branch != "zeta" {
		t.Fatalf("actions = %#v, want alpha before zeta", got)
	}
}
