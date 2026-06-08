package app

import (
	"context"
	"errors"
	"fmt"

	"github.com/thisguymartin/grove/internal/domain/agent"
	"github.com/thisguymartin/grove/internal/domain/review"
	"github.com/thisguymartin/grove/internal/domain/workspace"
)

type GitClient interface {
	Root(context.Context, string) (workspace.RepoRoot, error)
	BaseBranch(context.Context, workspace.RepoRoot) (workspace.BranchName, error)
	Worktrees(context.Context, workspace.RepoRoot) ([]workspace.Worktree, error)
}

type Reviews interface {
	PullRequests(context.Context, workspace.RepoRoot) ([]review.PullRequest, error)
}

type Agents interface {
	Sessions(context.Context) ([]agent.Session, error)
}

type ServiceConfig struct {
	Git     GitClient
	Reviews Reviews
	Agents  Agents
}

type Service struct {
	git     GitClient
	reviews Reviews
	agents  Agents
}

func NewService(cfg ServiceConfig) *Service {
	return &Service{
		git:     cfg.Git,
		reviews: cfg.Reviews,
		agents:  cfg.Agents,
	}
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

	var prs []review.PullRequest
	if s.reviews != nil {
		var err error
		prs, err = s.reviews.PullRequests(ctx, root)
		if err != nil {
			if !isOptionalToolUnavailable(err) {
				return workspace.Workspace{}, fmt.Errorf("load pull requests: %w", err)
			}
			prs = nil
		}
	}

	if s.agents != nil {
		if _, err := s.agents.Sessions(ctx); err != nil {
			return workspace.Workspace{}, fmt.Errorf("load agent sessions: %w", err)
		}
	}

	prBranches := pullRequestBranches(prs)
	statuses := make([]workspace.WorktreeStatus, 0, len(worktrees))
	for _, worktree := range worktrees {
		statuses = append(statuses, workspace.WorktreeStatus{
			Worktree: worktree,
			Clean:    true,
			HasPR:    hasPullRequest(worktree, base, prBranches),
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

func hasPullRequest(worktree workspace.Worktree, base workspace.BranchName, prBranches map[workspace.BranchName]struct{}) bool {
	if baselineHasPR(worktree, base) {
		return true
	}

	_, ok := prBranches[worktree.Branch]
	return ok
}

func pullRequestBranches(prs []review.PullRequest) map[workspace.BranchName]struct{} {
	branches := make(map[workspace.BranchName]struct{}, len(prs))
	for _, pr := range prs {
		if pr.Branch != "" {
			branches[workspace.BranchName(pr.Branch)] = struct{}{}
		}
	}
	return branches
}

type optionalToolUnavailable interface {
	OptionalToolUnavailable() bool
}

func isOptionalToolUnavailable(err error) bool {
	var unavailable optionalToolUnavailable
	return errors.As(err, &unavailable) && unavailable.OptionalToolUnavailable()
}
