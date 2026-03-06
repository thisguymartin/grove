#!/usr/bin/env bash
# resource-monitor.sh — CPU/Memory monitor for AI agent and dev tool processes
#
# Shows resource usage for claude, gemini, opencode, and lazygit processes.
#
# Designed to run in a loop: while true; do clear; ./resource-monitor.sh; sleep 5; done

set -euo pipefail

BOLD='\033[1m'
GREEN='\033[32m'
YELLOW='\033[33m'
RED='\033[31m'
CYAN='\033[36m'
DIM='\033[2m'
RESET='\033[0m'

echo -e "${BOLD}${CYAN}Resource Monitor${RESET}  ${DIM}$(date '+%Y-%m-%d %H:%M:%S')${RESET}"
echo ""

# Collect all AI/dev tool processes
proc_output=""
for proc_name in claude gemini opencode lazygit; do
    matches=$(ps -eo pid,pcpu,pmem,rss,etime,comm 2>/dev/null \
        | grep -i "$proc_name" \
        | grep -v grep \
        | grep -v "resource-monitor" || true)
    if [[ -n "$matches" ]]; then
        proc_output+="$matches"$'\n'
    fi
done

# Remove trailing newlines and empty lines
proc_output=$(echo "$proc_output" | sed '/^[[:space:]]*$/d')

if [[ -z "$proc_output" ]]; then
    echo -e "  ${DIM}No AI agent or dev tool processes running${RESET}"
else
    printf "  ${BOLD}%-8s %-7s %-7s %-8s %-12s %s${RESET}\n" "PID" "CPU%" "MEM%" "RSS" "ELAPSED" "PROCESS"
    printf "  ${DIM}"
    printf '%s' "$(printf '%.0s-' {1..55})"
    printf "${RESET}\n"

    echo "$proc_output" | while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        pid=$(echo "$line" | awk '{print $1}')
        cpu=$(echo "$line" | awk '{print $2}')
        mem=$(echo "$line" | awk '{print $3}')
        rss_kb=$(echo "$line" | awk '{print $4}')
        etime=$(echo "$line" | awk '{print $5}')
        comm=$(echo "$line" | awk '{print $6}')
        comm=$(basename "$comm" 2>/dev/null || echo "$comm")

        # Convert RSS to human readable
        if (( rss_kb >= 1048576 )); then
            rss="$(( rss_kb / 1048576 ))G"
        elif (( rss_kb >= 1024 )); then
            rss="$(( rss_kb / 1024 ))M"
        else
            rss="${rss_kb}K"
        fi

        # Color CPU usage
        cpu_int=${cpu%%.*}
        cpu_int=${cpu_int:-0}
        if (( cpu_int >= 80 )); then
            cpu_color="$RED"
        elif (( cpu_int >= 40 )); then
            cpu_color="$YELLOW"
        else
            cpu_color="$GREEN"
        fi

        printf "  %-8s ${cpu_color}%-7s${RESET} %-7s %-8s %-12s ${BOLD}%s${RESET}\n" \
            "$pid" "${cpu}%" "${mem}%" "$rss" "$etime" "$comm"
    done
fi

echo ""

# System summary
echo -e "  ${BOLD}System${RESET}"

if command -v sysctl &>/dev/null; then
    total_mem_bytes=$(sysctl -n hw.memsize 2>/dev/null || echo 0)
    total_mem_gb=$(( total_mem_bytes / 1073741824 ))

    # Memory pressure from vm_stat
    page_size=$(pagesize 2>/dev/null || echo 4096)
    pages_active=$(vm_stat 2>/dev/null | awk '/Pages active/ {gsub(/\./,"",$3); print $3}' || echo 0)
    pages_wired=$(vm_stat 2>/dev/null | awk '/Pages wired/ {gsub(/\./,"",$4); print $4}' || echo 0)
    pages_compressed=$(vm_stat 2>/dev/null | awk '/Pages occupied by compressor/ {gsub(/\./,"",$5); print $5}' || echo 0)

    used_pages=$(( pages_active + pages_wired + pages_compressed ))
    used_gb=$(( (used_pages * page_size) / 1073741824 ))

    # Color memory usage
    mem_pct=$(( (used_gb * 100) / (total_mem_gb > 0 ? total_mem_gb : 1) ))
    if (( mem_pct >= 85 )); then
        mem_color="$RED"
    elif (( mem_pct >= 65 )); then
        mem_color="$YELLOW"
    else
        mem_color="$GREEN"
    fi

    echo -e "  Memory: ${mem_color}${used_gb}G${RESET} / ${total_mem_gb}G (${mem_pct}%)"
fi

# CPU load average
load=$(sysctl -n vm.loadavg 2>/dev/null | tr -d '{}' | xargs || uptime | awk -F'load averages?: ' '{print $2}')
cores=$(sysctl -n hw.ncpu 2>/dev/null || echo "?")
echo -e "  Load:   ${load}  ${DIM}(${cores} cores)${RESET}"
