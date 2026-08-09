#!/usr/bin/env bash
# Traces a command under a permissive Seatbelt profile and reports the paths it
# touched that the aibox profile does NOT already allow -- i.e. the candidates
# for widening.
#
#   tools/trace.sh <label> <command> [args...]
set -euo pipefail

label="${1:?usage: trace.sh <label> <command> [args...]}"; shift
trace="/tmp/aibox-trace-$label.sb"; rm -f "$trace"
ws="$(mktemp -d "$HOME/aibox-trace-ws.XXXXXX")"
trap 'rm -rf "$ws"' EXIT

echo "== tracing: $* (cwd=$ws) ==" >&2
( cd "$ws" && sandbox-exec -p "(version 1)(trace \"$trace\")" "$@" ) >/dev/null 2>&1 \
    || echo "(command exited nonzero -- fine for tracing)" >&2

[ -f "$trace" ] || { echo "no trace produced" >&2; exit 1; }

# Prefixes the aibox profile already allows (kept in sync with src/profile.rs).
allowed_prefixes=(
    /usr /bin /sbin /System /Library /private/etc /private/var/db
    /nix /run/current-system /opt
    /dev/null /dev/zero /dev/random /dev/urandom /dev/dtracehelper
    /private/tmp /private/var/folders
    "$ws"
    "$HOME/.claude" "$HOME/.claude.json" "$HOME/.pi" "$HOME/.codex" "$HOME/.cargo" "$HOME/.rustup"
    "$HOME/.config/opencode" "$HOME/.config/fish" "$HOME/.config/delta"
    "$HOME/.local/share/opencode" "$HOME/.local/share/fish"
    "$HOME/.gradle" "$HOME/.m2" "$HOME/.clipboard-images"
)

covered() {
    local p="$1" pre
    [ "$p" = "/" ] && return 0
    for pre in "${allowed_prefixes[@]}"; do
        [ "$p" = "$pre" ] && return 0
        case "$p" in "$pre"/*) return 0 ;; esac
    done
    return 1
}

echo "== paths touched but NOT yet allowed ==" >&2
grep -oE '"/[^"]*"' "$trace" | tr -d '"' | sort -u | while IFS= read -r p; do
    covered "$p" || printf '%s\n' "$p"
done
