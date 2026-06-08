package git

import (
	"os"
	"strings"
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

func TestParseWorktreePorcelainBareRecord(t *testing.T) {
	got, err := ParseWorktreePorcelain("worktree /path/to/bare-source\nbare\n")
	if err != nil {
		t.Fatalf("ParseWorktreePorcelain returned error: %v", err)
	}
	if len(got) != 1 {
		t.Fatalf("len(worktrees) = %d, want 1", len(got))
	}

	wt := got[0]
	if string(wt.Path) != "/path/to/bare-source" {
		t.Fatalf("worktree[0].Path = %q, want %q", wt.Path, "/path/to/bare-source")
	}
	if !wt.Bare {
		t.Fatalf("worktree[0].Bare = false, want true")
	}
	if wt.Head != "" {
		t.Fatalf("worktree[0].Head = %q, want empty", wt.Head)
	}
	if wt.Branch != "" {
		t.Fatalf("worktree[0].Branch = %q, want empty", wt.Branch)
	}
}

func TestParseWorktreePorcelainBareAndLinkedRecords(t *testing.T) {
	got, err := ParseWorktreePorcelain(strings.Join([]string{
		"worktree /path/to/bare-source",
		"bare",
		"",
		"worktree /path/to/linked-worktree",
		"HEAD abcd1234abcd1234abcd1234abcd1234abcd1234",
		"branch refs/heads/main",
		"",
	}, "\n"))
	if err != nil {
		t.Fatalf("ParseWorktreePorcelain returned error: %v", err)
	}
	if len(got) != 2 {
		t.Fatalf("len(worktrees) = %d, want 2", len(got))
	}
	if !got[0].Bare {
		t.Fatalf("worktree[0].Bare = false, want true")
	}
	if got[1].Bare {
		t.Fatalf("worktree[1].Bare = true, want false")
	}
	if got[1].Head != "abcd1234abcd1234abcd1234abcd1234abcd1234" {
		t.Fatalf("worktree[1].Head = %q, want %q", got[1].Head, "abcd1234abcd1234abcd1234abcd1234abcd1234")
	}
	if got[1].Branch != "main" {
		t.Fatalf("worktree[1].Branch = %q, want %q", got[1].Branch, "main")
	}
}

func TestParseWorktreePorcelainMalformedInput(t *testing.T) {
	tests := []struct {
		name string
		in   string
		want string
	}{
		{
			name: "worktree missing value",
			in:   "worktree\n",
			want: "line 1: worktree requires a value",
		},
		{
			name: "HEAD missing value",
			in:   "worktree /repo/grove\nHEAD\n",
			want: "line 2: HEAD requires a value",
		},
		{
			name: "branch missing value",
			in:   "worktree /repo/grove\nHEAD 1111111111111111111111111111111111111111\nbranch\n",
			want: "line 3: branch requires a value",
		},
		{
			name: "record missing HEAD",
			in:   "worktree /repo/grove\nbranch refs/heads/main\n",
			want: "line 1: missing HEAD",
		},
		{
			name: "HEAD before worktree",
			in:   "HEAD abc\n",
			want: "line 1: HEAD before worktree",
		},
		{
			name: "branch before worktree",
			in:   "branch refs/heads/main\n",
			want: "line 1: branch before worktree",
		},
		{
			name: "detached before worktree",
			in:   "detached\n",
			want: "line 1: detached before worktree",
		},
		{
			name: "locked before worktree",
			in:   "locked\n",
			want: "line 1: locked before worktree",
		},
		{
			name: "bare before worktree",
			in:   "bare\n",
			want: "line 1: bare before worktree",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			_, err := ParseWorktreePorcelain(tt.in)
			if err == nil {
				t.Fatalf("ParseWorktreePorcelain returned nil error, want %q", tt.want)
			}
			if !strings.Contains(err.Error(), tt.want) {
				t.Fatalf("ParseWorktreePorcelain error = %q, want containing %q", err.Error(), tt.want)
			}
		})
	}
}
