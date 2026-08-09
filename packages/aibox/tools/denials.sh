#!/usr/bin/env bash
# Runs a command under the CURRENT aibox profile and reports the sandbox
# denials it triggered (unredacted, from the unified log). These are the paths
# to consider adding to src/profile.rs.
#
#   tools/denials.sh <label> <command> [args...]
set -euo pipefail

here="$(cd "$(dirname "$0")/.." && pwd)"
host="$here/target/release/aibox-host"
[ -x "$host" ] || host="$here/target/debug/aibox-host"

label="${1:?usage: denials.sh <label> <command> [args...]}"; shift

ws="$(mktemp -d "$HOME/aibox-hard-ws.XXXXXX")"
prof="/tmp/aibox-$label.sb"
"$host" profile "$ws" > "$prof"
cap="/tmp/aibox-denials-$label.log"; : > "$cap"
# Run output goes inside the workspace (read-write) so the harness can fstat its
# own stdout fd; a copy is kept in /tmp for inspection after cleanup.
out="$ws/run.out"
trap 'cp -f "$out" "/tmp/aibox-run-$label.out" 2>/dev/null; rm -rf "$ws"' EXIT

log stream --style compact --predicate 'eventMessage CONTAINS "deny("' > "$cap" 2>&1 &
logpid=$!
sleep 1.2

echo "== run: $* (cwd=$ws) ==" >&2
( cd "$ws" && sandbox-exec -f "$prof" "$@" ) > "$out" 2>&1 || echo "(exit $?)" >&2
sleep 1.5
kill "$logpid" 2>/dev/null || true

echo "== run output (tail) ==" >&2
tail -6 "$out" >&2
echo >&2
echo "== unique denials: <proc> <op> <path> ==" >&2
grep -oE 'Sandbox: [^ ]+\([0-9]+\) deny\([0-9]+\) [a-z*.-]+ .*' "$cap" \
    | sed -E 's/Sandbox: ([^ (]+)\([0-9]+\) deny\([0-9]+\) ([a-z*.-]+) (.*)$/\1\t\2\t\3/' \
    | sort -u
