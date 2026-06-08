package git

import (
	"os"
	"testing"
)

func TestParseWorktreePorcelain(t *testing.T) {
	input, err := os.ReadFile("testdata/worktree-list-porcelain.txt")
	if err != nil {
		t.Fatal(err)
	}

	got, err := ParseWorktreePorcelain(string(input))
	if err != nil {
		t.Fatalf("ParseWorktreePorcelain returned error: %v", err)
	}

	if len(got) != 4 {
		t.Fatalf("len(worktrees) = %d, want 4", len(got))
	}

	tests := []struct {
		index  int
		path   string
		branch string
		head   string
		locked bool
	}{
		{0, "/repo/grove", "main", "1111111111111111111111111111111111111111", false},
		{1, "/repo/.worktrees/feat-go-tui", "feat/go-tui", "2222222222222222222222222222222222222222", false},
		{2, "/repo/.worktrees/detached-check", "", "3333333333333333333333333333333333333333", false},
		{3, "/repo/.worktrees/locked", "fix/install", "4444444444444444444444444444444444444444", true},
	}

	for _, tt := range tests {
		wt := got[tt.index]
		if string(wt.Path) != tt.path {
			t.Fatalf("worktree[%d].Path = %q, want %q", tt.index, wt.Path, tt.path)
		}
		if string(wt.Branch) != tt.branch {
			t.Fatalf("worktree[%d].Branch = %q, want %q", tt.index, wt.Branch, tt.branch)
		}
		if wt.Head != tt.head {
			t.Fatalf("worktree[%d].Head = %q, want %q", tt.index, wt.Head, tt.head)
		}
		if wt.Locked != tt.locked {
			t.Fatalf("worktree[%d].Locked = %v, want %v", tt.index, wt.Locked, tt.locked)
		}
	}
}
