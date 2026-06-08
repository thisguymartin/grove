package main

import (
	"context"
	"fmt"
	"io"
	"os"
	"strings"
)

var version = "0.1.0-dev"

func main() {
	os.Exit(run(context.Background(), os.Args[1:], os.Stdout, os.Stderr))
}

func run(ctx context.Context, args []string, stdout io.Writer, stderr io.Writer) int {
	_ = ctx

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
	case "status", "ls", "tui":
		fmt.Fprintf(stderr, "%s is not wired yet\n", args[0])
		return 2
	default:
		fmt.Fprintf(stderr, "unknown command %q\n", args[0])
		printShortUsage(stderr)
		return 2
	}
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
