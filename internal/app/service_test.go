package app

import (
	"context"
	"errors"
	"strings"
	"testing"
	"time"

	"github.com/thisguymartin/grove/internal/domain/agent"
	"github.com/thisguymartin/grove/internal/domain/review"
	"github.com/thisguymartin/grove/internal/domain/workspace"
)

type fakeGit struct {
	root      workspace.RepoRoot
	rootErr   error
	base      workspace.BranchName
	baseErr   error
	worktrees []workspace.Worktree
	treeErr   error
	statuses  map[workspace.WorktreePath]workspace.GitStatus
	statusErr error
}

func (f fakeGit) Root(context.Context, string) (workspace.RepoRoot, error) {
	return f.root, f.rootErr
}
func (f fakeGit) BaseBranch(context.Context, workspace.RepoRoot) (workspace.BranchName, error) {
	return f.base, f.baseErr
}
func (f fakeGit) Worktrees(context.Context, workspace.RepoRoot) ([]workspace.Worktree, error) {
	return f.worktrees, f.treeErr
}
func (f fakeGit) Inspect(context.Context, workspace.RepoRoot, workspace.BranchName, []workspace.Worktree) (map[workspace.WorktreePath]workspace.GitStatus, error) {
	return f.statuses, f.statusErr
}

type fakeReviews struct {
	prs []review.PullRequest
	err error
}

func (f fakeReviews) PullRequests(context.Context, workspace.RepoRoot) ([]review.PullRequest, error) {
	return f.prs, f.err
}

type fakeAgents struct {
	sessions []agent.Session
	err      error
}

func (f fakeAgents) Sessions(context.Context, workspace.RepoRoot, []workspace.Worktree) ([]agent.Session, error) {
	return f.sessions, f.err
}

func TestServiceBuildsActionableSnapshot(t *testing.T) {
	generated := time.Date(2026, 7, 14, 12, 30, 0, 0, time.FixedZone("MST", -7*60*60))
	worktrees := []workspace.Worktree{
		{Path: "/repo/grove", Branch: "main"},
		{Path: "/repo/failed", Branch: "feat/failed"},
		{Path: "/repo/ready", Branch: "feat/ready"},
		{Path: "/repo/merged", Branch: "feat/merged"},
	}
	svc := NewService(ServiceConfig{
		Git: fakeGit{root: "/repo/grove", base: "main", worktrees: worktrees, statuses: map[workspace.WorktreePath]workspace.GitStatus{
			"/repo/grove":  {},
			"/repo/failed": {Ahead: 2},
			"/repo/ready":  {Ahead: 3},
			"/repo/merged": {Ahead: 1, Merged: true},
		}},
		Reviews: fakeReviews{prs: []review.PullRequest{{Branch: "feat/failed", Number: 17, State: "OPEN", Checks: "failed", CheckDetails: []string{"test: failure"}}}},
		Agents:  fakeAgents{sessions: []agent.Session{{Branch: "feat/ready", Editor: "codex", Command: "codex", Path: "/repo/ready", Tab: "feat-ready", PaneID: 4}}},
		Now:     func() time.Time { return generated },
	})

	got, err := svc.Status(context.Background(), "/repo/grove")
	if err != nil {
		t.Fatalf("Status returned error: %v", err)
	}
	if got.SchemaVersion != 1 || got.GeneratedAt.Location() != time.UTC || got.Repository.Root != "/repo/grove" || got.Repository.Base != "main" {
		t.Fatalf("snapshot metadata = %#v", got)
	}
	if got.Integrations.Git.State != workspace.IntegrationAvailable || got.Integrations.GitHub.State != workspace.IntegrationAvailable || got.Integrations.Zellij.State != workspace.IntegrationAvailable {
		t.Fatalf("integrations = %#v", got.Integrations)
	}
	byBranch := statusMap(got.Statuses)
	if byBranch["feat/failed"].Checks != workspace.CheckStateFailed || byBranch["feat/failed"].PRNumber != 17 {
		t.Fatalf("failed status = %#v", byBranch["feat/failed"])
	}
	if !byBranch["feat/ready"].PREligible || byBranch["feat/ready"].Agent != "codex" || len(byBranch["feat/ready"].Panes) != 1 {
		t.Fatalf("ready status = %#v", byBranch["feat/ready"])
	}
	if got.NextActions[0].Kind != workspace.NextActionOpenChecks || got.NextActions[1].Kind != workspace.NextActionCreatePR || got.NextActions[2].Kind != workspace.NextActionRemove {
		t.Fatalf("next actions = %#v", got.NextActions)
	}
}

func TestServiceNeverSuggestsPRWhenGitHubUnknown(t *testing.T) {
	worktrees := []workspace.Worktree{{Path: "/repo/grove", Branch: "main"}, {Path: "/repo/feature", Branch: "feat/one"}}
	svc := NewService(ServiceConfig{
		Git:     fakeGit{root: "/repo/grove", base: "main", worktrees: worktrees, statuses: map[workspace.WorktreePath]workspace.GitStatus{"/repo/feature": {Ahead: 4}}},
		Reviews: fakeReviews{err: errors.New("gh auth required")},
	})

	got, err := svc.Status(context.Background(), ".")
	if err != nil {
		t.Fatalf("Status returned error: %v", err)
	}
	if got.Integrations.GitHub.State != workspace.IntegrationUnknown || !strings.Contains(got.Integrations.GitHub.Reason, "auth") {
		t.Fatalf("GitHub health = %#v", got.Integrations.GitHub)
	}
	if statusMap(got.Statuses)["feat/one"].PREligible {
		t.Fatal("feature is PR eligible while GitHub state is unknown")
	}
	for _, action := range got.NextActions {
		if action.Kind == workspace.NextActionCreatePR {
			t.Fatalf("unexpected create PR action: %#v", action)
		}
	}
}

func TestServicePRRulesExcludeBaseDetachedBareAndMerged(t *testing.T) {
	worktrees := []workspace.Worktree{
		{Path: "/repo/grove", Branch: "main"},
		{Path: "/repo/detached", Head: "abc"},
		{Path: "/repo/bare", Branch: "feat/bare", Bare: true},
		{Path: "/repo/merged", Branch: "feat/merged"},
		{Path: "/repo/ready", Branch: "feat/ready"},
	}
	svc := NewService(ServiceConfig{
		Git: fakeGit{root: "/repo/grove", base: "main", worktrees: worktrees, statuses: map[workspace.WorktreePath]workspace.GitStatus{
			"/repo/grove": {Ahead: 2}, "/repo/detached": {Ahead: 2}, "/repo/bare": {Ahead: 2}, "/repo/merged": {Ahead: 2, Merged: true}, "/repo/ready": {Ahead: 2},
		}},
		Reviews: fakeReviews{},
	})

	got, err := svc.Status(context.Background(), ".")
	if err != nil {
		t.Fatalf("Status returned error: %v", err)
	}
	byBranch := statusMap(got.Statuses)
	if byBranch["main"].PREligible || byBranch[""].PREligible || byBranch["feat/bare"].PREligible || byBranch["feat/merged"].PREligible || !byBranch["feat/ready"].PREligible {
		t.Fatalf("eligibility = %#v", byBranch)
	}
}

func TestServiceTreatsMergedPRAsMergedWorktree(t *testing.T) {
	worktrees := []workspace.Worktree{{Path: "/repo/merged", Branch: "feat/merged"}}
	svc := NewService(ServiceConfig{
		Git:     fakeGit{root: "/repo", base: "main", worktrees: worktrees, statuses: map[workspace.WorktreePath]workspace.GitStatus{"/repo/merged": {Ahead: 1}}},
		Reviews: fakeReviews{prs: []review.PullRequest{{Branch: "feat/merged", State: "MERGED", Number: 9}}},
	})
	got, err := svc.Status(context.Background(), ".")
	if err != nil {
		t.Fatal(err)
	}
	if !got.Statuses[0].Merged || got.NextActions[0].Kind != workspace.NextActionRemove {
		t.Fatalf("snapshot = %#v", got)
	}
}

func TestServiceGitFailuresAreFatal(t *testing.T) {
	tests := []struct {
		name  string
		git   fakeGit
		phase string
	}{
		{name: "root", git: fakeGit{rootErr: errors.New("not a repo")}, phase: "resolve repo root"},
		{name: "base", git: fakeGit{root: "/repo", baseErr: errors.New("no base")}, phase: "resolve base branch"},
		{name: "worktrees", git: fakeGit{root: "/repo", base: "main", treeErr: errors.New("list failed")}, phase: "list worktrees"},
		{name: "inspect", git: fakeGit{root: "/repo", base: "main", statusErr: errors.New("status failed")}, phase: "inspect worktrees"},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			_, err := NewService(ServiceConfig{Git: tt.git}).Status(context.Background(), ".")
			if err == nil || !strings.Contains(err.Error(), tt.phase) {
				t.Fatalf("error = %v, want %q", err, tt.phase)
			}
		})
	}
}

func TestServiceRequiresGit(t *testing.T) {
	_, err := NewService(ServiceConfig{}).Status(context.Background(), ".")
	if err == nil || !strings.Contains(err.Error(), "git client is required") {
		t.Fatalf("error = %v", err)
	}
}

func statusMap(statuses []workspace.WorktreeStatus) map[workspace.BranchName]workspace.WorktreeStatus {
	result := make(map[workspace.BranchName]workspace.WorktreeStatus, len(statuses))
	for _, status := range statuses {
		result[status.Worktree.Branch] = status
	}
	return result
}
