package status

import (
	"strings"
	"testing"
	"time"

	"github.com/thisguymartin/grove/internal/domain/workspace"
)

func TestCompactAdaptsDeterministicallyAtSupportedWidths(t *testing.T) {
	snapshot := testSnapshot()
	for _, width := range []int{80, 120, 160} {
		t.Run(string(rune(width)), func(t *testing.T) {
			first := Compact(snapshot, width)
			second := Compact(snapshot, width)
			if first != second {
				t.Fatal("render output changed between calls")
			}
			for _, line := range strings.Split(strings.TrimSuffix(first, "\n"), "\n") {
				if len([]rune(line)) > width {
					t.Fatalf("line is %d columns at width %d: %q", len([]rune(line)), width, line)
				}
			}
			if width == 80 && strings.Contains(first, "CHECKS") {
				t.Fatalf("narrow output contains wide columns:\n%s", first)
			}
			if width >= 120 {
				for _, want := range []string{"PR", "CHECKS", "AGENT", "codex"} {
					if !strings.Contains(first, want) {
						t.Fatalf("wide output missing %q:\n%s", want, first)
					}
				}
			}
		})
	}
}

func TestFullIncludesPathsDetailsPanesAndIntegrationReasons(t *testing.T) {
	snapshot := testSnapshot()
	got := Full(snapshot, 120)
	for _, want := range []string{"Integrations", "github: unknown (gh auth required)", "path: /repo/feature", "upstream: ahead 2, behind 0", "check: test: failure", "pane: feat-one #4 codex"} {
		if !strings.Contains(got, want) {
			t.Fatalf("full output missing %q:\n%s", want, got)
		}
	}
}

func TestWidthFromColumns(t *testing.T) {
	if got := WidthFromColumns(""); got != 120 {
		t.Fatalf("empty COLUMNS = %d", got)
	}
	if got := WidthFromColumns("80"); got != 80 {
		t.Fatalf("COLUMNS=80 = %d", got)
	}
	if got := WidthFromColumns("12"); got != 40 {
		t.Fatalf("COLUMNS=12 = %d", got)
	}
}

func testSnapshot() workspace.Workspace {
	statuses := []workspace.WorktreeStatus{
		{Worktree: workspace.Worktree{Path: "/repo/grove", Branch: "main"}, Clean: true, PRKnown: false, Checks: workspace.CheckStateUnknown},
		{Worktree: workspace.Worktree{Path: "/repo/feature", Branch: "feat/one"}, Clean: true, Ahead: 2, PRKnown: true, HasPR: true, PRNumber: 17, PRState: "open", Checks: workspace.CheckStateFailed, CheckDetails: []string{"test: failure"}, Agent: "codex", Panes: []workspace.Pane{{Tab: "feat-one", PaneID: 4, Command: "codex", Path: "/repo/feature"}}},
	}
	return workspace.Workspace{
		SchemaVersion: 1,
		GeneratedAt:   time.Date(2026, 7, 14, 19, 30, 0, 0, time.UTC),
		Repository:    workspace.Repository{Root: "/repo/grove", Base: "main"},
		Integrations: workspace.Integrations{
			Git:    workspace.IntegrationHealth{State: workspace.IntegrationAvailable},
			GitHub: workspace.IntegrationHealth{State: workspace.IntegrationUnknown, Reason: "gh auth required"},
			Zellij: workspace.IntegrationHealth{State: workspace.IntegrationAvailable},
		},
		Statuses:    statuses,
		NextActions: workspace.ScoreNextActions(statuses),
	}
}
