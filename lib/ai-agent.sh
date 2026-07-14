#!/usr/bin/env bash

GROVE_AI_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/grove"
GROVE_AI_CONFIG_FILE="$GROVE_AI_CONFIG_DIR/config"

grove_is_supported_ai() {
    case "${1:-}" in
        codex|opencode|claude|gemini|none) return 0 ;;
        *) return 1 ;;
    esac
}

grove_read_saved_ai() {
    [[ -f "$GROVE_AI_CONFIG_FILE" ]] || return 0

    local line key value
    IFS= read -r line < "$GROVE_AI_CONFIG_FILE" || true
    IFS='=' read -r key value <<< "$line"

    if [[ "$key" != "default_ai" ]] || ! grove_is_supported_ai "$value"; then
        echo "Error: Invalid default_ai in $GROVE_AI_CONFIG_FILE" >&2
        return 1
    fi

    printf '%s\n' "$value"
}

grove_resolve_ai() {
    local explicit_ai="${1:-}"
    local resolved_ai=""

    if [[ -n "$explicit_ai" ]]; then
        resolved_ai="$explicit_ai"
    elif [[ -n "${AI_EDITOR:-}" ]]; then
        resolved_ai="$AI_EDITOR"
    elif [[ -f "$GROVE_AI_CONFIG_FILE" ]]; then
        resolved_ai="$(grove_read_saved_ai)" || return 1
    else
        resolved_ai="opencode"
    fi

    if ! grove_is_supported_ai "$resolved_ai"; then
        echo "Error: Unsupported AI agent '$resolved_ai'. Use codex, opencode, claude, gemini, or none." >&2
        return 1
    fi

    printf '%s\n' "$resolved_ai"
}

grove_require_ai() {
    local resolved_ai
    resolved_ai="$(grove_require_ai_choice "${1:-}")" || return 1

    if ! command -v "$resolved_ai" >/dev/null 2>&1; then
        echo "Error: AI agent '$resolved_ai' is not installed. Install it or choose another with: grove <agent> ." >&2
        return 1
    fi

    printf '%s\n' "$resolved_ai"
}

grove_require_ai_choice() {
    local resolved_ai
    resolved_ai="$(grove_resolve_ai "${1:-}")" || return 1

    if [[ "$resolved_ai" == "none" ]]; then
        echo "Error: No default AI agent is configured. Pass one explicitly, for example: grove codex ." >&2
        return 1
    fi

    printf '%s\n' "$resolved_ai"
}
