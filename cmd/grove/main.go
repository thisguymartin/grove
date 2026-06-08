package main

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"os"
	"strings"

	"github.com/thisguymartin/grove/internal/adapters/git"
	"github.com/thisguymartin/grove/internal/app"
)

var version = "0.1.0-dev"

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
	case "ls", "tui":
		fmt.Fprintf(stderr, "%s is not wired yet\n", args[0])
		return 2
	default:
		fmt.Fprintf(stderr, "unknown command %q\n", args[0])
		printShortUsage(stderr)
		return 2
	}
}

func runStatus(ctx context.Context, args []string, stdout io.Writer, stderr io.Writer) int {
	if len(args) == 0 {
		fmt.Fprintln(stderr, "status is not wired yet")
		return 2
	}
	if len(args) != 1 || args[0] != "--json" {
		fmt.Fprintln(stderr, "unsupported status flags")
		return 2
	}

	svc := app.NewService(app.ServiceConfig{
		Git: git.NewClient(nil),
	})
	snapshot, err := svc.Status(ctx, ".")
	if err != nil {
		fmt.Fprintln(stderr, err)
		return 1
	}
	if err := json.NewEncoder(stdout).Encode(snapshot); err != nil {
		fmt.Fprintf(stderr, "encode status json: %v\n", err)
		return 1
	}
	return 0
}

func printUsage(w io.Writer) {
	fmt.Fprintln(w, strings.TrimSpace(`
Usage:
  grove status --json
  grove ls
  grove tui
  grove version
  grove help

Experimental Go CLI for Grove. Bash launch scripts remain available during migration.
`))
	fmt.Fprintln(w)
}

func printShortUsage(w io.Writer) {
	fmt.Fprintln(w, "Run `grove help` for available commands.")
}
