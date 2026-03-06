#!/usr/bin/env bash
# ai-status.sh — Live AI session dashboard for Grove
#
# Shows active Claude processes, token usage today, and recent sessions
# parsed from ~/.claude/projects/ JSONL logs.
#
# Designed to run in a loop: while true; do clear; ./ai-status.sh; sleep 10; done

set -euo pipefail

CLAUDE_DIR="$HOME/.claude/projects"

BOLD='\033[1m'
GREEN='\033[32m'
YELLOW='\033[33m'
CYAN='\033[36m'
MAGENTA='\033[35m'
DIM='\033[2m'
RED='\033[31m'
RESET='\033[0m'

# ---------------------------------------------------------------------------
# Header
# ---------------------------------------------------------------------------
echo -e "${BOLD}${CYAN}AI Agent Dashboard${RESET}  ${DIM}$(date '+%Y-%m-%d %H:%M:%S')${RESET}"
echo ""

# ---------------------------------------------------------------------------
# Active Claude agents (running processes)
# ---------------------------------------------------------------------------
echo -e "${BOLD}Active Agents${RESET}"
agent_count=0
for editor in claude gemini opencode; do
    active=$(pgrep -a -f "$editor" 2>/dev/null | grep -v grep | grep -v "ai-status" | grep -v "resource-monitor" || true)
    if [[ -z "$active" ]]; then
        continue
    fi
    while IFS= read -r proc; do
        pid=$(echo "$proc" | awk '{print $1}')
        cwd=$(lsof -p "$pid" -a -d cwd -Fn 2>/dev/null | grep '^n' | head -1 | sed 's/^n//' || echo "unknown")
        branch=$(git -C "$cwd" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "?")
        project=$(basename "$cwd")
        case "$editor" in
            claude)   icon="${GREEN}●${RESET}"; label="Claude" ;;
            gemini)   icon="${YELLOW}●${RESET}"; label="Gemini" ;;
            opencode) icon="${MAGENTA}●${RESET}"; label="OpenCode" ;;
        esac
        echo -e "  ${icon} ${BOLD}${project}${RESET} ${DIM}/${branch}${RESET}  ${DIM}[${label}] pid:${pid}${RESET}"
        agent_count=$((agent_count + 1))
    done <<< "$active"
done
if [[ "$agent_count" -eq 0 ]]; then
    echo -e "  ${DIM}No active AI agent processes${RESET}"
fi
echo ""

# ---------------------------------------------------------------------------
# Token usage — parsed from JSONL, today + all-time per project
# ---------------------------------------------------------------------------
echo -e "${BOLD}Token Usage (Claude)${RESET}"

if [[ ! -d "$CLAUDE_DIR" ]]; then
    echo -e "  ${DIM}No Claude session data found at $CLAUDE_DIR${RESET}"
else
    python3 - "$CLAUDE_DIR" <<'PYEOF'
import os, sys, json, datetime, pathlib

claude_dir = sys.argv[1]
today = datetime.date.today().isoformat()

projects = {}  # project_slug -> {today_in, today_out, total_in, total_out, last_ts, last_model, last_branch}

for proj_dir in sorted(pathlib.Path(claude_dir).iterdir()):
    if not proj_dir.is_dir():
        continue

    slug = proj_dir.name
    # Convert path slug back to readable name: take last 2 segments
    parts = slug.replace("-Users-", "").split("-")
    # Find a readable project name from the path slug
    display = slug.split("-")[-1] if "-" in slug else slug
    # Better: grab last path component
    readable = slug.replace("-Users-thisguymartin-", "~/").replace("-", "/", slug.count("-") - slug.replace("-Users-thisguymartin-", "").count("-"))
    # Simplest: just use last 2 dash-separated segments as project/branch hint
    segs = slug.split("-")
    display = segs[-1] if len(segs) >= 1 else slug

    data = {"today_in": 0, "today_out": 0, "today_cache_read": 0,
            "total_in": 0, "total_out": 0, "total_cache_read": 0,
            "last_ts": None, "last_model": "", "last_branch": "", "display": display,
            "session_count": 0, "slug": slug}

    for jfile in sorted(proj_dir.glob("*.jsonl"), key=lambda f: f.stat().st_mtime, reverse=True):
        data["session_count"] += 1
        mtime = datetime.datetime.fromtimestamp(jfile.stat().st_mtime)
        if data["last_ts"] is None:
            data["last_ts"] = mtime

        try:
            with open(jfile) as f:
                for line in f:
                    line = line.strip()
                    if not line:
                        continue
                    try:
                        obj = json.loads(line)
                    except json.JSONDecodeError:
                        continue

                    if not data["last_branch"] and obj.get("gitBranch"):
                        data["last_branch"] = obj["gitBranch"]

                    msg = obj.get("message", {})
                    if not data["last_model"] and msg.get("model"):
                        data["last_model"] = msg["model"]

                    usage = msg.get("usage", {})
                    if not usage:
                        continue

                    inp = usage.get("input_tokens", 0) or 0
                    out = usage.get("output_tokens", 0) or 0
                    cache_read = usage.get("cache_read_input_tokens", 0) or 0

                    data["total_in"] += inp
                    data["total_out"] += out
                    data["total_cache_read"] += cache_read

                    if mtime.date().isoformat() == today:
                        data["today_in"] += inp
                        data["today_out"] += out
                        data["today_cache_read"] += cache_read
        except Exception:
            continue

    if data["total_in"] > 0 or data["total_out"] > 0:
        projects[slug] = data

# Sort by most recently active
sorted_projects = sorted(projects.values(), key=lambda x: x["last_ts"] or datetime.datetime.min, reverse=True)

# Claude Sonnet 4.6 pricing (per million tokens)
PRICE_IN = 3.0
PRICE_OUT = 15.0
PRICE_CACHE_READ = 0.30

def fmt_k(n):
    if n >= 1_000_000:
        return f"{n/1_000_000:.1f}M"
    if n >= 1000:
        return f"{n/1000:.0f}k"
    return str(n)

def cost(inp, out, cache_read):
    return (inp * PRICE_IN + out * PRICE_OUT + cache_read * PRICE_CACHE_READ) / 1_000_000

CYAN = '\033[36m'
DIM = '\033[2m'
BOLD = '\033[1m'
RESET = '\033[0m'
YELLOW = '\033[33m'
GREEN = '\033[32m'
MAGENTA = '\033[35m'

if not sorted_projects:
    print(f"  {DIM}No token data found{RESET}")
else:
    # Header row
    print(f"  {'Project':<28} {'Today (in/out)':<20} {'All-time (in/out)':<22} {'Cost today':<12} {'Model'}")
    print(f"  {'-'*28} {'-'*20} {'-'*22} {'-'*12} {'-'*20}")
    for p in sorted_projects[:10]:
        today_str = f"{fmt_k(p['today_in'])} / {fmt_k(p['today_out'])}"
        total_str = f"{fmt_k(p['total_in'])} / {fmt_k(p['total_out'])}"
        cost_today = cost(p['today_in'], p['today_out'], p['today_cache_read'])
        cost_str = f"${cost_today:.3f}" if cost_today > 0 else "-"
        model_short = p['last_model'].replace("claude-", "").replace("-20", " ") if p['last_model'] else "?"

        # Readable project name from slug
        proj_display = p['slug'].replace("-Users-thisguymartin-", "").replace("-personal-workspace-", "~/").replace("-Desktop-", "~/Desktop/").replace("-", "/")
        # Just show last 2 path parts
        parts = proj_display.rstrip("/").split("/")
        proj_name = "/".join(parts[-2:]) if len(parts) >= 2 else proj_display
        if len(proj_name) > 27:
            proj_name = "..." + proj_name[-24:]

        print(f"  {CYAN}{proj_name:<28}{RESET} {today_str:<20} {DIM}{total_str:<22}{RESET} {YELLOW}{cost_str:<12}{RESET} {DIM}{model_short}{RESET}")

PYEOF
fi

echo ""

# ---------------------------------------------------------------------------
# Recent sessions
# ---------------------------------------------------------------------------
echo -e "${BOLD}Recent Sessions (Claude)${RESET}"

if [[ -d "$CLAUDE_DIR" ]]; then
    python3 - "$CLAUDE_DIR" <<'PYEOF'
import os, sys, json, datetime, pathlib

claude_dir = sys.argv[1]

sessions = []

for proj_dir in pathlib.Path(claude_dir).iterdir():
    if not proj_dir.is_dir():
        continue
    slug = proj_dir.name

    for jfile in proj_dir.glob("*.jsonl"):
        mtime = datetime.datetime.fromtimestamp(jfile.stat().st_mtime)
        branch = ""
        model = ""
        total_in = 0
        total_out = 0

        try:
            with open(jfile) as f:
                for line in f:
                    line = line.strip()
                    if not line:
                        continue
                    try:
                        obj = json.loads(line)
                    except Exception:
                        continue
                    if not branch and obj.get("gitBranch"):
                        branch = obj["gitBranch"]
                    msg = obj.get("message", {})
                    if not model and msg.get("model"):
                        model = msg["model"]
                    usage = msg.get("usage", {})
                    if usage:
                        total_in += usage.get("input_tokens", 0) or 0
                        total_out += usage.get("output_tokens", 0) or 0
        except Exception:
            continue

        if total_in > 0 or total_out > 0:
            proj_display = slug.replace("-Users-thisguymartin-", "").replace("-personal-workspace-", "~/").replace("-Desktop-", "~/Desktop/").replace("-", "/")
            parts = proj_display.rstrip("/").split("/")
            proj_name = "/".join(parts[-2:]) if len(parts) >= 2 else proj_display

            sessions.append({
                "mtime": mtime,
                "proj": proj_name,
                "branch": branch,
                "model": model.replace("claude-", "").replace("-20", " ") if model else "?",
                "total_in": total_in,
                "total_out": total_out,
                "session_id": jfile.stem[:8],
            })

sessions.sort(key=lambda x: x["mtime"], reverse=True)

DIM = '\033[2m'
CYAN = '\033[36m'
GREEN = '\033[32m'
RESET = '\033[0m'
BOLD = '\033[1m'

def fmt_k(n):
    if n >= 1_000_000:
        return f"{n/1_000_000:.1f}M"
    if n >= 1000:
        return f"{n/1000:.0f}k"
    return str(n)

def time_ago(dt):
    diff = datetime.datetime.now() - dt
    s = int(diff.total_seconds())
    if s < 60: return f"{s}s ago"
    if s < 3600: return f"{s//60}m ago"
    if s < 86400: return f"{s//3600}h ago"
    return f"{s//86400}d ago"

if not sessions:
    print(f"  \033[2mNo sessions found\033[0m")
else:
    for s in sessions[:8]:
        branch_str = f" {DIM}/{s['branch']}{RESET}" if s['branch'] else ""
        tokens_str = f"{fmt_k(s['total_in'])}in / {fmt_k(s['total_out'])}out"
        age = time_ago(s['mtime'])
        print(f"  {CYAN}{s['proj']}{RESET}{branch_str}  {DIM}{age:<12}{RESET} {tokens_str:<20} {DIM}{s['model']}{RESET}")

PYEOF
fi
