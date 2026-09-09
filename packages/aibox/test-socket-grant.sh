#!/usr/bin/env bash
# Does `aibox allow` grant a unix socket along with the files beside it?
#
# On Linux the answer is structural: a grant is a bind mount, and a bind carries
# a socket in like anything else. On macOS it is an empirical question -- files
# are widened by a consumed sandbox extension, but connecting is a
# network-outbound operation, and whether the kernel honours a file extension
# for that is undocumented. This test answers it either way.
#
# A stand-in harness repeatedly connects to a socket outside its policy. Expect
# DENIED, then OK once ALLOW is sent, then DENIED again after DENY.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
command -v nc >/dev/null 2>&1 || { echo "nc is required to probe a unix socket"; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "python3 is required to serve one"; exit 1; }
cargo build --manifest-path "$here/Cargo.toml" >/dev/null 2>&1
bin="$here/target/debug/aibox-host"

ws="$HOME/aibox-sockgrant-ws";  rm -rf "$ws";      mkdir -p "$ws"
# The agent directory is deliberately somewhere no static rule mentions: not a
# temp directory, not the workspace, not a toolchain path.
agentdir="$HOME/aibox-sockgrant"; rm -rf "$agentdir"; mkdir -p "$agentdir"
agent="$agentdir/agent.sock"
log="$ws/log"; : > "$log"
manifest="$here/target/sockgrant-manifest"; : > "$manifest"
profile="$here/target/sockgrant.policy"; "$bin" profile "$ws" > "$profile"
sock="/tmp/aibox-sockgrant.sock"
export AIBOX_DENIAL_LOG="$here/target/sockgrant-denials.db"
rm -f "$sock" "$AIBOX_DENIAL_LOG" "$here/target/sockgrant-denials.lock"
secret="test-control-secret"

# A stand-in for ssh-agent: accept a connection, close it, keep listening.
cat > "$ws/server.py" <<'PY'
import os, socket, sys
path = sys.argv[1]
try:
    os.unlink(path)
except FileNotFoundError:
    pass
s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
s.bind(path)
s.listen(16)
while True:
    c, _ = s.accept()
    c.close()
PY
python3 "$ws/server.py" "$agent" &
server_pid=$!
sleep 0.6

# If the probe cannot reach the socket from OUTSIDE the sandbox, everything
# below would report a denial that is really a broken fixture.
nc -U -w 1 "$agent" </dev/null >/dev/null 2>&1 \
    || { echo "fixture broken: cannot reach $agent from outside the sandbox"; kill "$server_pid"; exit 1; }

harness="$ws/harness.sh"
cat > "$harness" <<EOF
#!/usr/bin/env bash
for i in \$(seq 1 30); do
  if nc -U -w 1 "$agent" </dev/null >/dev/null 2>&1; then
    echo "\$i OK" >> "$log"
  else
    echo "\$i DENIED" >> "$log"
  fi
  sleep 0.3
done
EOF
chmod +x "$harness"

cleanup() { kill "$broker_pid" 2>/dev/null || true; kill "$server_pid" 2>/dev/null || true; rm -f "$sock"; }
trap cleanup EXIT

( cd "$ws" && exec "$bin" broker "$sock" "$profile" "$manifest" "$secret" -- "$harness" ) &
broker_pid=$!

sleep 1.5
echo "--- initial (expect DENIED) ---"; tail -2 "$log"
echo ">> ALLOW $agentdir : $("$bin" ctl "$sock" "$secret" "ALLOW $agentdir")"
sleep 1.5
echo "--- after ALLOW ---"; tail -2 "$log"
granted="$(tail -2 "$log" | grep -c OK || true)"
echo ">> DENY $agentdir : $("$bin" ctl "$sock" "$secret" "DENY $agentdir")"
sleep 1.5
echo "--- after DENY (expect DENIED) ---"; tail -2 "$log"

wait "$broker_pid" 2>/dev/null || true
echo
echo "=== transitions in full log ==="
awk 'NR==1{p=$2} $2!=p{print "  line "$1": "p" -> "$2; p=$2}' "$log"
echo
if [[ "$granted" -gt 0 ]]; then
    echo "VERDICT: a grant carries the socket -- \`aibox allow\` covers sockets on $(uname -s)."
else
    echo "VERDICT: the socket stayed unreachable while its directory was granted."
    echo "         On macOS that means a consumed extension does NOT authorize"
    echo "         network-outbound, and socket grants need a different mechanism."
    exit 1
fi
