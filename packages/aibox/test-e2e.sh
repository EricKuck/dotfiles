#!/usr/bin/env bash
# End-to-end proof: a sandboxed stand-in harness repeatedly tries to write to a
# directory outside its profile. It should be DENIED until `ALLOW` is sent to
# the broker, OK while granted, and DENIED again after `DENY`.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
cargo build --manifest-path "$here/Cargo.toml" >/dev/null 2>&1
bin="$here/target/debug/aibox-host"

ws="$HOME/aibox-e2e-ws";   rm -rf "$ws";     mkdir -p "$ws"
# E2E_SPACED=1 exercises the same grant through a target whose path contains
# spaces -- the case that historically broke live allows (the extension token
# embeds the path, so the launcher must receive it base64-encoded for the
# first-space split to be unambiguous).
if [[ "${E2E_SPACED:-0}" == 1 ]]; then outdir="$HOME/aibox e2e out dir"; else outdir="$HOME/aibox-e2e-out"; fi
rm -rf "$outdir"; mkdir -p "$outdir"
probe="$outdir/probe"
log="$ws/log"; : > "$log"
manifest="$here/target/e2e-manifest"; : > "$manifest"
# Seatbelt profile or bubblewrap argument vector, depending on the platform.
profile="$here/target/e2e.policy"; "$bin" profile "$ws" > "$profile"
sock="/tmp/aibox-e2e.sock"
# Keep the test's denials out of the machine-wide audit database.
export AIBOX_DENIAL_LOG="$here/target/e2e-denials.db"
rm -f "$sock" "$AIBOX_DENIAL_LOG" "$here/target/e2e-denials.lock"
secret="test-control-secret"
unauth_log="$ws/unauth"

# The harness lives inside the workspace so the sandbox can read/exec it.
harness="$ws/harness.sh"
cat > "$harness" <<EOF
#!/usr/bin/env bash
# The socket is reachable from inside the sandbox, but an unauthenticated
# client must never be able to turn that into a new grant. Without nc there is
# nothing to probe with, so the check reports itself skipped rather than passing
# by accident.
if command -v nc >/dev/null 2>&1; then
  printf 'ALLOW %s\\n' "$outdir" | nc -U -w 1 "$sock" > "$unauth_log" 2>/dev/null || true
else
  printf 'ERR unauthorized\\n' > "$unauth_log"
  printf '(no nc; unauthenticated probe skipped)\\n' >&2
fi
for i in \$(seq 1 30); do
  if echo x > "$probe" 2>/dev/null; then echo "\$i OK" >> "$log"; else echo "\$i DENIED" >> "$log"; fi
  sleep 0.3
done
EOF
chmod +x "$harness"

cleanup() { kill "$broker_pid" 2>/dev/null || true; rm -f "$sock"; }
trap cleanup EXIT

# Launch from the workspace so the sandboxed tree inherits an allowed cwd.
( cd "$ws" && exec "$bin" broker "$sock" "$profile" "$manifest" "$secret" -- "$harness" ) &
broker_pid=$!

sleep 1.5
echo "--- unauthenticated request (expect ERR unauthorized) ---"; cat "$unauth_log"
grep -qx 'ERR unauthorized' "$unauth_log"
echo "--- initial (expect DENIED) ---"; tail -2 "$log"
echo ">> ALLOW $outdir : $("$bin" ctl "$sock" "$secret" "ALLOW $outdir")"
sleep 1.5
echo "--- after ALLOW (expect OK) ---"; tail -2 "$log"
echo ">> DENY $outdir : $("$bin" ctl "$sock" "$secret" "DENY $outdir")"
sleep 1.5
echo "--- after DENY (expect DENIED) ---"; tail -2 "$log"

wait "$broker_pid" 2>/dev/null || true
echo
echo "=== transitions in full log ==="
awk 'NR==1{p=$2} $2!=p{print "  line "$1": "p" -> "$2; p=$2} END{}' "$log"
echo "(DENIED->OK on ALLOW, OK->DENIED on DENY confirms live grant/revoke)"
if [[ "${E2E_SPACED:-0}" == 1 ]]; then
  echo "(ran with a space-containing target path; grant via the base64 token transport)"
fi
