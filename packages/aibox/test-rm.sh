#!/usr/bin/env bash
# Proves `aibox rm` deletes workspace state by its full path and refuses to
# remove a workspace that still has a live broker session.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
cargo build --manifest-path "$here/Cargo.toml" >/dev/null 2>&1

base="$HOME/aibox-rm-smoke"
ws="$base/ws"
out="$base/out"
export AIBOX_STATE_ROOT="$base/state"
rm -rf "$base"
mkdir -p "$ws" "$out"
cleanup() {
  kill "${session:-}" 2>/dev/null || true
  rm -rf "$base"
}
trap cleanup EXIT

cli() { ( cd "$ws" && "$here/bin/aibox" "$@" ); }

# A stopped workspace remains listed until explicit removal, including when the
# caller uses the full workspace path returned by `aibox list`.
cli allow "$out" >/dev/null
workspace="$(cli list | awk -F '\t' 'NR == 1 { print $1 }')"
[[ "$workspace" == "$ws" ]]
cli rm "$workspace" | grep -qx "removed workspace state: $workspace"
[[ -z "$(cli list)" ]]

cat > "$ws/claude" <<'EOF'
#!/bin/bash
sleep 30
EOF
chmod +x "$ws/claude"
export PATH="$ws:$PATH"
( cd "$ws" && exec "$here/bin/claude" ) >/dev/null 2>&1 & session=$!
sleep 1
if cli rm > "$base/rm.out" 2>&1; then
  echo 'aibox rm unexpectedly removed a live workspace' >&2
  exit 1
fi
grep -q 'still has live session' "$base/rm.out"
kill "$session" 2>/dev/null || true
wait "$session" 2>/dev/null || true
cli rm | grep -q '^removed workspace state:'
[[ -z "$(cli list)" ]]
echo 'workspace state removal: OK'
