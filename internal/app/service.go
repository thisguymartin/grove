package app

import (
	"context"
	"errors"
	"fmt"

	"github.com/thisguymartin/grove/internal/domain/workspace"
)

type GitClient interface {
	Root(context.Context, string) (workspace.RepoRoot, error)
	BaseBranch(context.Context, workspace.RepoRoot) (workspace.BranchName, error)
	Worktrees(context.Context, workspace.RepoRoot) ([]workspace.Worktree, error)
}

type ServiceConfig struct {
	Git GitClient
}

type Service struct {
	git GitClient
}

func NewService(cfg ServiceConfig) *Service {
	return &Service{git: cfg.Git}
}

func (s *Service) Status(ctx context.Context, path string) (workspace.Workspace, error) {
	if s.git == nil {
		return workspace.Workspace{}, errors.New("git client is required")
	}

	root, err := s.git.Root(ctx, path)
	if err != nil {
		return workspace.Workspace{}, fmt.Errorf("resolve repo root: %w", err)
	}

	base, err := s.git.BaseBranch(ctx, root)
	if err != nil {
		return workspace.Workspace{}, fmt.Errorf("resolve base branch: %w", err)
	}

	worktrees, err := s.git.Worktrees(ctx, root)
	if err != nil {
		return workspace.Workspace{}, fmt.Errorf("list worktrees: %w", err)
	}

	statuses := make([]workspace.WorktreeStatus, 0, len(worktrees))
	for _, worktree := range worktrees {
		statuses = append(statuses, workspace.WorktreeStatus{
			Worktree: worktree,
			Clean:    true,
			HasPR:    baselineHasPR(worktree, base),
			Checks:   workspace.CheckStateUnknown,
		})
	}

	return workspace.Workspace{
		Root:        root,
		Base:        base,
		Worktrees:   worktrees,
		Statuses:    statuses,
		NextActions: workspace.ScoreNextActions(statuses),
	}, nil
}

func baselineHasPR(worktree workspace.Worktree, base workspace.BranchName) bool {
	// Until PR metadata lands, treat branchless and bare worktrees as PR-ineligible.
	return worktree.Branch == base || worktree.Branch == "" || worktree.Bare
}
