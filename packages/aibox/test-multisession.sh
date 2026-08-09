#!/usr/bin/env bash
# Proves two harnesses can run in one workspace and receive the same live
# workspace-wide allow/deny transition.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
cargo build --manifest-path "$here/Cargo.toml" >/dev/null 2>&1

ws="$HOME/aibox-multi-ws";       rm -rf "$ws"; mkdir -p "$ws"
outdir="$HOME/aibox-multi-out"; rm -rf "$outdir"; mkdir -p "$outdir"
export AIBOX_STATE_ROOT="$HOME/.aibox/test-multi-state"; rm -rf "$AIBOX_STATE_ROOT"

cat > "$ws/claude" <<EOF
#!/bin/bash
label="\${!#}"
log="$ws/\$label.log"
for i in \$(seq 1 40); do
  if echo x > "$outdir/\$label" 2>/dev/null; then echo "\$i OK" >> "\$log"; else echo "\$i DENIED" >> "\$log"; fi
  sleep 0.15
done
EOF
chmod +x "$ws/claude"
export PATH="$ws:$PATH"

cli() { ( cd "$ws" && "$here/bin/aibox" "$@" ); }
cleanup() {
  kill "${one:-}" "${two:-}" 2>/dev/null || true
  rm -rf "$ws" "$outdir" "$AIBOX_STATE_ROOT"
}
trap cleanup EXIT

( cd "$ws" && exec "$here/bin/claude" one ) >/dev/null 2>&1 & one=$!
( cd "$ws" && exec "$here/bin/claude" two ) >/dev/null 2>&1 & two=$!
sleep 1

status="$(cli status)"
printf '%s\n' "$status"
[[ "$(grep -c $'\trunning$' <<< "$status")" -eq 2 ]]
echo "$(cli allow "$outdir")"
sleep 0.8
for label in one two; do tail -1 "$ws/$label.log" | grep -q ' OK$'; done
echo "$(cli deny "$outdir")"
sleep 0.8
for label in one two; do tail -1 "$ws/$label.log" | grep -q ' DENIED$'; done

echo 'multi-session workspace grants: OK'
