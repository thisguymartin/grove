package status

import (
	"fmt"
	"strconv"
	"strings"

	"github.com/thisguymartin/grove/internal/domain/workspace"
)

const defaultWidth = 120

func WidthFromColumns(value string) int {
	width, err := strconv.Atoi(strings.TrimSpace(value))
	if err != nil || width <= 0 {
		return defaultWidth
	}
	if width < 40 {
		return 40
	}
	return width
}

func Compact(snapshot workspace.Workspace, width int) string {
	if width <= 0 {
		width = defaultWidth
	}
	var out strings.Builder
	header := fmt.Sprintf("Grove  %s  base %s  updated %s", snapshot.Repository.Root, snapshot.Repository.Base, snapshot.GeneratedAt.Format("15:04 UTC"))
	out.WriteString(truncate(header, width))
	out.WriteByte('\n')

	actions := actionsByPath(snapshot.NextActions)
	if width < 100 {
		branchWidth := min(24, max(12, width/4))
		gitWidth := min(20, max(12, width/5))
		nextWidth := max(8, width-branchWidth-gitWidth-4)
		writeRow(&out, []cell{{"BRANCH", branchWidth}, {"GIT", gitWidth}, {"NEXT", nextWidth}})
		for _, status := range snapshot.Statuses {
			writeRow(&out, []cell{{status.Worktree.DisplayName(), branchWidth}, {gitSummary(status), gitWidth}, {actionLabel(actions[status.Worktree.Path]), nextWidth}})
		}
		return strings.TrimRight(out.String(), " \n") + "\n"
	}

	branchWidth := 24
	gitWidth := 20
	prWidth := 12
	checksWidth := 10
	agentWidth := 12
	if width >= 150 {
		branchWidth, gitWidth, prWidth, checksWidth, agentWidth = 30, 24, 16, 12, 16
	}
	nextWidth := max(10, width-branchWidth-gitWidth-prWidth-checksWidth-agentWidth-10)
	columns := []cell{{"BRANCH", branchWidth}, {"GIT", gitWidth}, {"PR", prWidth}, {"CHECKS", checksWidth}, {"AGENT", agentWidth}, {"NEXT", nextWidth}}
	writeRow(&out, columns)
	for _, status := range snapshot.Statuses {
		writeRow(&out, []cell{
			{status.Worktree.DisplayName(), branchWidth},
			{gitSummary(status), gitWidth},
			{prSummary(status, snapshot.Repository.Base), prWidth},
			{checkSummary(status, snapshot.Repository.Base), checksWidth},
			{emptyDash(status.Agent), agentWidth},
			{actionLabel(actions[status.Worktree.Path]), nextWidth},
		})
	}
	return strings.TrimRight(out.String(), " \n") + "\n"
}

func Full(snapshot workspace.Workspace, width int) string {
	var out strings.Builder
	out.WriteString(Compact(snapshot, width))
	out.WriteString("\nIntegrations\n")
	writeIntegration(&out, "git", snapshot.Integrations.Git)
	writeIntegration(&out, "github", snapshot.Integrations.GitHub)
	writeIntegration(&out, "zellij", snapshot.Integrations.Zellij)

	for _, status := range snapshot.Statuses {
		fmt.Fprintf(&out, "\n%s\n", status.Worktree.DisplayName())
		fmt.Fprintf(&out, "  path: %s\n", status.Worktree.Path)
		fmt.Fprintf(&out, "  upstream: ahead %d, behind %d\n", status.Ahead, status.Behind)
		if status.PRKnown {
			if status.HasPR {
				fmt.Fprintf(&out, "  pull request: #%d %s %s\n", status.PRNumber, status.PRState, status.PRURL)
			} else {
				out.WriteString("  pull request: none\n")
			}
		} else {
			out.WriteString("  pull request: unknown\n")
		}
		for _, detail := range status.CheckDetails {
			fmt.Fprintf(&out, "  check: %s\n", detail)
		}
		for _, pane := range status.Panes {
			fmt.Fprintf(&out, "  pane: %s #%d %s (%s)\n", pane.Tab, pane.PaneID, pane.Command, pane.Path)
		}
	}
	return out.String()
}

type cell struct {
	value string
	width int
}

func writeRow(out *strings.Builder, cells []cell) {
	for i, cell := range cells {
		if i > 0 {
			out.WriteString("  ")
		}
		value := truncate(cell.value, cell.width)
		if i == len(cells)-1 {
			out.WriteString(value)
			continue
		}
		fmt.Fprintf(out, "%-*s", cell.width, value)
	}
	out.WriteByte('\n')
}

func truncate(value string, width int) string {
	if width <= 0 {
		return ""
	}
	runes := []rune(value)
	if len(runes) <= width {
		return value
	}
	if width == 1 {
		return "…"
	}
	return string(runes[:width-1]) + "…"
}

func gitSummary(status workspace.WorktreeStatus) string {
	parts := make([]string, 0, 3)
	if status.DirtyFiles > 0 {
		parts = append(parts, fmt.Sprintf("%d dirty", status.DirtyFiles))
	}
	if status.Ahead > 0 {
		parts = append(parts, fmt.Sprintf("+%d", status.Ahead))
	}
	if status.Behind > 0 {
		parts = append(parts, fmt.Sprintf("-%d", status.Behind))
	}
	if status.Merged {
		parts = append(parts, "merged")
	}
	if len(parts) == 0 {
		return "clean"
	}
	return strings.Join(parts, " ")
}

func prSummary(status workspace.WorktreeStatus, base workspace.BranchName) string {
	if !status.PRKnown {
		return "unknown"
	}
	if !status.HasPR {
		if status.Worktree.Branch == base || status.Worktree.Branch == "" || status.Worktree.Bare {
			return "-"
		}
		return "none"
	}
	return fmt.Sprintf("#%d %s", status.PRNumber, status.PRState)
}

func checkSummary(status workspace.WorktreeStatus, base workspace.BranchName) string {
	if status.HasPR || !status.PRKnown {
		return string(status.Checks)
	}
	if status.Worktree.Branch == base || status.Worktree.Branch == "" || status.Worktree.Bare || status.Checks == workspace.CheckStateUnknown {
		return "-"
	}
	return string(status.Checks)
}

func actionLabel(action workspace.NextAction) string {
	if action.Kind == workspace.NextActionIdle || action.Label == "" {
		return "-"
	}
	return action.Label
}

func actionsByPath(actions []workspace.NextAction) map[workspace.WorktreePath]workspace.NextAction {
	result := make(map[workspace.WorktreePath]workspace.NextAction, len(actions))
	for _, action := range actions {
		result[action.WorktreePath] = action
	}
	return result
}

func writeIntegration(out *strings.Builder, name string, health workspace.IntegrationHealth) {
	fmt.Fprintf(out, "  %s: %s", name, health.State)
	if health.Reason != "" {
		fmt.Fprintf(out, " (%s)", health.Reason)
	}
	out.WriteByte('\n')
}

func emptyDash(value string) string {
	if value == "" {
		return "-"
	}
	return value
}

func min(a, b int) int {
	if a < b {
		return a
	}
	return b
}

func max(a, b int) int {
	if a > b {
		return a
	}
	return b
}
