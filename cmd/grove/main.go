package main

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"os"
	"strings"

	"github.com/thisguymartin/grove/internal/adapters/git"
	"github.com/thisguymartin/grove/internal/adapters/github"
	"github.com/thisguymartin/grove/internal/adapters/zellij"
	"github.com/thisguymartin/grove/internal/app"
	"github.com/thisguymartin/grove/internal/domain/workspace"
	statusview "github.com/thisguymartin/grove/internal/presentation/status"
)

var version = "0.1.0-dev"

type statusService interface {
	Status(context.Context, string) (workspace.Workspace, error)
}

var newStatusService = func() statusService {
	return app.NewService(app.ServiceConfig{
		Git:     git.NewClient(nil),
		Reviews: github.NewClient(nil),
		Agents:  zellij.NewClient(nil),
	})
}

func main() {
	os.Exit(run(context.Background(), os.Args[1:], os.Stdout, os.Stderr))
}

func run(ctx context.Context, args []string, stdout io.Writer, stderr io.Writer) int {
	if len(args) == 0 {
		printUsage(stdout)
		return 0
	}

	switch args[0] {
	case "help", "-h", "--help":
		printUsage(stdout)
		return 0
	case "version", "--version":
		fmt.Fprintln(stdout, version)
		return 0
	case "status":
		return runStatus(ctx, args[1:], stdout, stderr)
	default:
		fmt.Fprintf(stderr, "unknown command %q\n", args[0])
		printShortUsage(stderr)
		return 2
	}
}

func runStatus(ctx context.Context, args []string, stdout io.Writer, stderr io.Writer) int {
	path, full, jsonOutput, err := parseStatusArgs(args)
	if err != nil {
		fmt.Fprintln(stderr, err)
		return 2
	}

	snapshot, err := newStatusService().Status(ctx, path)
	if err != nil {
		fmt.Fprintln(stderr, err)
		return 1
	}
	if jsonOutput {
		if err := json.NewEncoder(stdout).Encode(snapshot); err != nil {
			fmt.Fprintf(stderr, "encode status json: %v\n", err)
			return 1
		}
		return 0
	}

	width := statusview.WidthFromColumns(os.Getenv("COLUMNS"))
	if full {
		fmt.Fprint(stdout, statusview.Full(snapshot, width))
	} else {
		fmt.Fprint(stdout, statusview.Compact(snapshot, width))
	}
	return 0
}

func parseStatusArgs(args []string) (path string, full bool, jsonOutput bool, err error) {
	path = "."
	pathSet := false
	for _, arg := range args {
		switch arg {
		case "--full":
			full = true
		case "--json":
			jsonOutput = true
		default:
			if strings.HasPrefix(arg, "-") {
				return "", false, false, fmt.Errorf("unsupported status flag %q", arg)
			}
			if pathSet {
				return "", false, false, errorsStatus("status accepts at most one path")
			}
			path = arg
			pathSet = true
		}
	}
	if full && jsonOutput {
		return "", false, false, errorsStatus("--full and --json are mutually exclusive")
	}
	return path, full, jsonOutput, nil
}

type errorsStatus string

func (e errorsStatus) Error() string { return string(e) }

func printUsage(w io.Writer) {
	fmt.Fprintln(w, strings.TrimSpace(`
Usage:
  grove status [path] [--full | --json]
  grove version
  grove help

Experimental status renderer for Grove's shell workflow.
`))
	fmt.Fprintln(w)
}

func printShortUsage(w io.Writer) {
	fmt.Fprintln(w, "Run `grove help` for available commands.")
}
