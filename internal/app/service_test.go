package app

import (
	"context"
	"testing"

	"github.com/thisguymartin/grove/internal/domain/workspace"
)

type fakeGit struct {
	root      workspace.RepoRoot
	base      workspace.BranchName
	worktrees []workspace.Worktree
}

func (f fakeGit) Root(context.Context, string) (workspace.RepoRoot, error) {
	return f.root, nil
}

func (f fakeGit) BaseBranch(context.Context, workspace.RepoRoot) (workspace.BranchName, error) {
	return f.base, nil
}

func (f fakeGit) Worktrees(context.Context, workspace.RepoRoot) ([]workspace.Worktree, error) {
	return f.worktrees, nil
}

func TestServiceStatusBuildsWorkspace(t *testing.T) {
	svc := NewService(ServiceConfig{
		Git: fakeGit{
			root: "/repo/grove",
			base: "main",
			worktrees: []workspace.Worktree{
				{Path: "/repo/grove", Branch: "main", Head: "abc"},
				{Path: "/repo/.worktrees/feat-go-tui", Branch: "feat/go-tui", Head: "def"},
			},
		},
	})

	got, err := svc.Status(context.Background(), "/repo/grove")
	if err != nil {
		t.Fatalf("Status returned error: %v", err)
	}

	if got.Root != "/repo/grove" {
		t.Fatalf("Root = %q, want /repo/grove", got.Root)
	}
	if got.Base != "main" {
		t.Fatalf("Base = %q, want main", got.Base)
	}
	if len(got.Worktrees) != 2 {
		t.Fatalf("len(Worktrees) = %d, want 2", len(got.Worktrees))
	}
}
