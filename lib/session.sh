#!/usr/bin/env bash

GROVE_ZELLIJ_SESSION_MAX_LENGTH=24

grove_session_name() {
    local repo_name="$1"
    local full_name="grove-${repo_name}"

    if (( ${#full_name} <= GROVE_ZELLIJ_SESSION_MAX_LENGTH )); then
        printf '%s\n' "$full_name"
        return 0
    fi

    local checksum readable_length
    checksum="$(printf '%s' "$repo_name" | cksum | awk '{printf "%06x", $1 % 16777216}')"
    readable_length=$((GROVE_ZELLIJ_SESSION_MAX_LENGTH - ${#checksum} - 7))
    printf 'grove-%s-%s\n' "${repo_name:0:$readable_length}" "$checksum"
}
