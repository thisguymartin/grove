package workspace

import "testing"

func TestWorktreeDisplayName(t *testing.T) {
	tests := []struct {
		name string
		in   Worktree
		want string
	}{
		{
			name: "uses branch when present",
			in:   Worktree{Branch: "feat/go-tui", Head: "1111111111111111111111111111111111111111"},
			want: "feat/go-tui",
		},
		{
			name: "uses bare label when bare",
			in:   Worktree{Bare: true},
			want: "bare",
		},
		{
			name: "truncates detached SHA",
			in:   Worktree{Head: "3333333333333333333333333333333333333333"},
			want: "detached@3333333",
		},
		{
			name: "keeps short detached HEAD",
			in:   Worktree{Head: "abc123"},
			want: "detached@abc123",
		},
		{
			name: "handles empty detached HEAD",
			in:   Worktree{},
			want: "detached@",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if got := tt.in.DisplayName(); got != tt.want {
				t.Fatalf("DisplayName() = %q, want %q", got, tt.want)
			}
		})
	}
}
