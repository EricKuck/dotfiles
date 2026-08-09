#!/usr/bin/env bash
# Exercises the aibox CLI end to end with a stand-in harness named `claude`:
# launch via the symlink, then drive `aibox allow`/`deny`/`status` from another
# process and confirm the running harness gains and loses the directory live.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
cargo build --manifest-path "$here/Cargo.toml" >/dev/null 2>&1

ws="$HOME/aibox-smoke-ws";   rm -rf "$ws";     mkdir -p "$ws"
outdir="$HOME/aibox-smoke-out"; rm -rf "$outdir"; mkdir -p "$outdir"
probe="$outdir/probe"
log="$ws/log"; : > "$log"

# Workspace state mirrors the full path; control sockets remain short and
# ephemeral under TMPDIR so they fit in sun_path (~104 chars).
export AIBOX_STATE_ROOT="$HOME/.aibox/test-cli-state"; rm -rf "$AIBOX_STATE_ROOT"

# Stand-in harness lives INSIDE the workspace so the sandbox can exec it, and on
# PATH so the wrapper resolves it as the "real" claude.
cat > "$ws/claude" <<EOF
#!/bin/bash
for i in \$(seq 1 24); do
  if echo x > "$probe" 2>/dev/null; then echo "\$i OK" >> "$log"; else echo "\$i DENIED" >> "$log"; fi
  sleep 0.3
done
EOF
chmod +x "$ws/claude"
export PATH="$ws:$PATH"

cli() { ( cd "$ws" && "$here/bin/aibox" "$@" ); }

cleanup() { kill "$sess" 2>/dev/null || true; }
trap cleanup EXIT

# Launch the session via the `claude` symlink, backgrounded.
( cd "$ws" && exec "$here/bin/claude" ) >/dev/null 2>&1 &
sess=$!

sleep 1.5
echo "== aibox status (expect running, none visible) =="; cli status
echo "== aibox list =="; cli list
echo
echo "-- harness log, initial (expect DENIED) --"; tail -2 "$log"
echo ">> aibox allow $outdir"; cli allow "$outdir"
sleep 1.5
echo "-- after allow (expect OK) --"; tail -2 "$log"
echo "== aibox status (expect $outdir visible) =="; cli status
echo ">> aibox deny $outdir"; cli deny "$outdir"
sleep 1.5
echo "-- after deny (expect DENIED) --"; tail -2 "$log"

wait "$sess" 2>/dev/null || true
echo
echo "=== transitions ==="
awk 'NR==1{p=$2} $2!=p{print "  line "$1": "p" -> "$2; p=$2}' "$log"
rm -rf "$ws" "$outdir" "$AIBOX_STATE_ROOT"
