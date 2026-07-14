package app

import (
	"context"
	"errors"
	"fmt"
	"strings"
	"time"

	"github.com/thisguymartin/grove/internal/domain/agent"
	"github.com/thisguymartin/grove/internal/domain/review"
	"github.com/thisguymartin/grove/internal/domain/workspace"
)

type GitClient interface {
	Root(context.Context, string) (workspace.RepoRoot, error)
	BaseBranch(context.Context, workspace.RepoRoot) (workspace.BranchName, error)
	Worktrees(context.Context, workspace.RepoRoot) ([]workspace.Worktree, error)
	Inspect(context.Context, workspace.RepoRoot, workspace.BranchName, []workspace.Worktree) (map[workspace.WorktreePath]workspace.GitStatus, error)
}

type Reviews interface {
	PullRequests(context.Context, workspace.RepoRoot) ([]review.PullRequest, error)
}

type Agents interface {
	Sessions(context.Context, workspace.RepoRoot, []workspace.Worktree) ([]agent.Session, error)
}

type ServiceConfig struct {
	Git     GitClient
	Reviews Reviews
	Agents  Agents
	Now     func() time.Time
}

type Service struct {
	git     GitClient
	reviews Reviews
	agents  Agents
	now     func() time.Time
}

func NewService(cfg ServiceConfig) *Service {
	now := cfg.Now
	if now == nil {
		now = time.Now
	}
	return &Service{git: cfg.Git, reviews: cfg.Reviews, agents: cfg.Agents, now: now}
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
	gitStatuses, err := s.git.Inspect(ctx, root, base, worktrees)
	if err != nil {
		return workspace.Workspace{}, fmt.Errorf("inspect worktrees: %w", err)
	}
	repositoryRoot := root
	if len(worktrees) > 0 && worktrees[0].Path != "" {
		repositoryRoot = workspace.RepoRoot(worktrees[0].Path)
	}

	integrations := workspace.Integrations{
		Git:    workspace.IntegrationHealth{State: workspace.IntegrationAvailable},
		GitHub: workspace.IntegrationHealth{State: workspace.IntegrationUnknown, Reason: "not configured"},
		Zellij: workspace.IntegrationHealth{State: workspace.IntegrationUnknown, Reason: "not configured"},
	}
	prs := map[workspace.BranchName]review.PullRequest{}
	prKnown := false
	if s.reviews != nil {
		rows, reviewErr := s.reviews.PullRequests(ctx, root)
		if reviewErr != nil {
			integrations.GitHub.Reason = conciseReason(reviewErr)
		} else {
			prKnown = true
			integrations.GitHub = workspace.IntegrationHealth{State: workspace.IntegrationAvailable}
			prs = pullRequestsByBranch(rows)
		}
	}

	var sessions []agent.Session
	if s.agents != nil {
		rows, agentErr := s.agents.Sessions(ctx, root, worktrees)
		if agentErr != nil {
			integrations.Zellij.Reason = conciseReason(agentErr)
		} else {
			sessions = rows
			integrations.Zellij = workspace.IntegrationHealth{State: workspace.IntegrationAvailable}
		}
	}

	statuses := make([]workspace.WorktreeStatus, 0, len(worktrees))
	for _, worktree := range worktrees {
		gitStatus := gitStatuses[worktree.Path]
		status := workspace.WorktreeStatus{
			Worktree:   worktree,
			Clean:      gitStatus.DirtyFiles == 0,
			DirtyFiles: gitStatus.DirtyFiles,
			Ahead:      gitStatus.Ahead,
			Behind:     gitStatus.Behind,
			Merged:     gitStatus.Merged,
			PRKnown:    prKnown,
			Checks:     workspace.CheckStateUnknown,
		}
		if pr, ok := prs[worktree.Branch]; ok {
			status.HasPR = true
			status.PRNumber = pr.Number
			status.PRURL = pr.URL
			status.PRState = strings.ToLower(pr.State)
			status.Checks = checkState(pr.Checks)
			status.CheckDetails = append([]string(nil), pr.CheckDetails...)
			status.Merged = status.Merged || strings.EqualFold(pr.State, "merged")
		}
		status.PREligible = prKnown && status.Ahead > 0 && !status.Merged && !status.HasPR && worktree.Branch != "" && worktree.Branch != base && !worktree.Bare
		for _, session := range sessions {
			if session.Branch != string(worktree.Branch) && !pathWithin(session.Path, string(worktree.Path)) {
				continue
			}
			if status.Agent == "" && session.Editor != "" {
				status.Agent = session.Editor
			}
			status.Panes = append(status.Panes, workspace.Pane{Tab: session.Tab, PaneID: session.PaneID, Command: session.Command, Path: session.Path})
		}
		statuses = append(statuses, status)
	}

	return workspace.Workspace{
		SchemaVersion: 1,
		GeneratedAt:   s.now().UTC(),
		Repository:    workspace.Repository{Root: repositoryRoot, Base: base},
		Integrations:  integrations,
		Statuses:      statuses,
		NextActions:   workspace.ScoreNextActions(statuses),
		Root:          repositoryRoot,
		Base:          base,
		Worktrees:     worktrees,
	}, nil
}

func pullRequestsByBranch(rows []review.PullRequest) map[workspace.BranchName]review.PullRequest {
	result := make(map[workspace.BranchName]review.PullRequest, len(rows))
	for _, pr := range rows {
		branch := workspace.BranchName(pr.Branch)
		if branch == "" {
			continue
		}
		current, exists := result[branch]
		if !exists || (!strings.EqualFold(current.State, "open") && strings.EqualFold(pr.State, "open")) {
			result[branch] = pr
		}
	}
	return result
}

func checkState(value string) workspace.CheckState {
	switch workspace.CheckState(strings.ToLower(value)) {
	case workspace.CheckStatePassing:
		return workspace.CheckStatePassing
	case workspace.CheckStatePending:
		return workspace.CheckStatePending
	case workspace.CheckStateFailed:
		return workspace.CheckStateFailed
	default:
		return workspace.CheckStateUnknown
	}
}

func pathWithin(path, root string) bool {
	return path == root || strings.HasPrefix(path, strings.TrimRight(root, "/")+"/")
}

func conciseReason(err error) string {
	if err == nil {
		return ""
	}
	return err.Error()
}
