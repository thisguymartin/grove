package app

import (
	"context"
	"errors"
	"strings"
	"testing"

	"github.com/thisguymartin/grove/internal/domain/workspace"
)

type fakeGit struct {
	root      workspace.RepoRoot
	rootErr   error
	base      workspace.BranchName
	baseErr   error
	worktrees []workspace.Worktree
	treeErr   error
}

func (f fakeGit) Root(context.Context, string) (workspace.RepoRoot, error) {
	if f.rootErr != nil {
		return "", f.rootErr
	}
	return f.root, nil
}

func (f fakeGit) BaseBranch(context.Context, workspace.RepoRoot) (workspace.BranchName, error) {
	if f.baseErr != nil {
		return "", f.baseErr
	}
	return f.base, nil
}

func (f fakeGit) Worktrees(context.Context, workspace.RepoRoot) ([]workspace.Worktree, error) {
	if f.treeErr != nil {
		return nil, f.treeErr
	}
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

func TestServiceStatusRequiresGitClient(t *testing.T) {
	svc := NewService(ServiceConfig{})

	_, err := svc.Status(context.Background(), "/repo/grove")
	if err == nil {
		t.Fatal("Status returned nil error, want git client required")
	}
	if !strings.Contains(err.Error(), "git client is required") {
		t.Fatalf("Status error = %q, want git client context", err.Error())
	}
}

func TestServiceStatusWrapsRootError(t *testing.T) {
	wantErr := errors.New("not a git repo")
	svc := NewService(ServiceConfig{
		Git: fakeGit{rootErr: wantErr},
	})

	_, err := svc.Status(context.Background(), "/repo/grove")
	assertWrappedError(t, err, "resolve repo root", wantErr)
}

func TestServiceStatusWrapsBaseBranchError(t *testing.T) {
	wantErr := errors.New("origin unavailable")
	svc := NewService(ServiceConfig{
		Git: fakeGit{
			root:    "/repo/grove",
			baseErr: wantErr,
		},
	})

	_, err := svc.Status(context.Background(), "/repo/grove")
	assertWrappedError(t, err, "resolve base branch", wantErr)
}

func TestServiceStatusWrapsWorktreesError(t *testing.T) {
	wantErr := errors.New("worktree list failed")
	svc := NewService(ServiceConfig{
		Git: fakeGit{
			root:    "/repo/grove",
			base:    "main",
			treeErr: wantErr,
		},
	})

	_, err := svc.Status(context.Background(), "/repo/grove")
	assertWrappedError(t, err, "list worktrees", wantErr)
}

func assertWrappedError(t *testing.T, err error, phase string, target error) {
	t.Helper()

	if err == nil {
		t.Fatalf("Status returned nil error, want %q", phase)
	}
	if !strings.Contains(err.Error(), phase) {
		t.Fatalf("Status error = %q, want phase %q", err.Error(), phase)
	}
	if !errors.Is(err, target) {
		t.Fatalf("Status error = %v, want wrapping %v", err, target)
	}
}
