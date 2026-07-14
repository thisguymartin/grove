package workspace

import (
	"encoding/json"
	"testing"
	"time"
)

func TestWorkspaceJSONSchemaVersionOne(t *testing.T) {
	snapshot := Workspace{
		SchemaVersion: 1,
		GeneratedAt:   time.Date(2026, 7, 14, 12, 0, 0, 0, time.UTC),
		Repository:    Repository{Root: "/repo", Base: "main"},
		Integrations: Integrations{
			Git:    IntegrationHealth{State: IntegrationAvailable},
			GitHub: IntegrationHealth{State: IntegrationUnknown, Reason: "gh unavailable"},
			Zellij: IntegrationHealth{State: IntegrationAvailable},
		},
		Statuses:    []WorktreeStatus{{Worktree: Worktree{Path: "/repo", Branch: "main"}, Clean: true, Checks: CheckStateUnknown}},
		NextActions: []NextAction{{Branch: "main", Kind: NextActionIdle, Label: "idle"}},
		Root:        "/internal-only",
		Base:        "internal-only",
	}

	data, err := json.Marshal(snapshot)
	if err != nil {
		t.Fatal(err)
	}
	var got map[string]json.RawMessage
	if err := json.Unmarshal(data, &got); err != nil {
		t.Fatal(err)
	}
	for _, key := range []string{"schema_version", "generated_at", "repository", "integrations", "worktrees", "next_actions"} {
		if _, ok := got[key]; !ok {
			t.Fatalf("schema missing %q: %s", key, data)
		}
	}
	for _, key := range []string{"root", "base", "statuses"} {
		if _, ok := got[key]; ok {
			t.Fatalf("schema unexpectedly exposes legacy field %q: %s", key, data)
		}
	}
}
