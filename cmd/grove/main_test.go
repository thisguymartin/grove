package main

import (
	"bytes"
	"context"
	"strings"
	"testing"
)

func TestRunHelpPrintsUsage(t *testing.T) {
	var stdout bytes.Buffer
	var stderr bytes.Buffer

	code := run(context.Background(), []string{"help"}, &stdout, &stderr)
	if code != 0 {
		t.Fatalf("run help exit code = %d, want 0; stderr=%q", code, stderr.String())
	}

	output := stdout.String()
	for _, want := range []string{"Usage:", "grove status --json", "grove tui", "grove ls"} {
		if !strings.Contains(output, want) {
			t.Fatalf("help output missing %q:\n%s", want, output)
		}
	}
}

func TestRunVersionPrintsVersion(t *testing.T) {
	var stdout bytes.Buffer
	var stderr bytes.Buffer

	code := run(context.Background(), []string{"version"}, &stdout, &stderr)
	if code != 0 {
		t.Fatalf("run version exit code = %d, want 0; stderr=%q", code, stderr.String())
	}

	if got := strings.TrimSpace(stdout.String()); got == "" || got == "dev" {
		t.Fatalf("version output = %q, want non-empty version label", got)
	}
}

func TestRunPlaceholderCommandsReportNotWired(t *testing.T) {
	for _, cmd := range []string{"status", "ls", "tui"} {
		t.Run(cmd, func(t *testing.T) {
			var stdout bytes.Buffer
			var stderr bytes.Buffer

			code := run(context.Background(), []string{cmd}, &stdout, &stderr)
			if code != 2 {
				t.Fatalf("%s exit code = %d, want 2", cmd, code)
			}
			if !strings.Contains(stderr.String(), cmd+" is not wired yet") {
				t.Fatalf("stderr missing not-wired message:\n%s", stderr.String())
			}
			if stdout.Len() != 0 {
				t.Fatalf("stdout = %q, want empty", stdout.String())
			}
		})
	}
}

func TestRunUnknownCommandReportsError(t *testing.T) {
	var stdout bytes.Buffer
	var stderr bytes.Buffer

	code := run(context.Background(), []string{"wat"}, &stdout, &stderr)
	if code != 2 {
		t.Fatalf("unknown command exit code = %d, want 2", code)
	}
	if !strings.Contains(stderr.String(), `unknown command "wat"`) {
		t.Fatalf("stderr missing unknown command:\n%s", stderr.String())
	}
	if stdout.Len() != 0 {
		t.Fatalf("stdout = %q, want empty", stdout.String())
	}
}
