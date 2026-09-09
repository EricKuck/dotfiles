#!/usr/bin/env bash
# Proves that harness activity drives the host keep-awake bridge. A fake
# caffeinate records its launch, avoiding a real power assertion in tests.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
cargo build --manifest-path "$here/Cargo.toml" >/dev/null 2>&1

base="$HOME/aibox-keepawake-smoke"
ws="$base/ws"
state="$base/state"
test_home="$base/home"
log="$base/caffeinate.log"
mkdir -p "$ws" "$state" "$test_home"
export AIBOX_STATE_ROOT="$state"
export AIBOX_ACTIVITY_POLL_SECONDS=0.05
rm -f "$log"

fake_caffeinate="$base/caffeinate"
cat > "$fake_caffeinate" <<EOF
#!/usr/bin/env bash
printf 'start %s\\n' "\$*" >> "$log"
trap 'exit 0' TERM INT
while :; do sleep 1; done
EOF
chmod +x "$fake_caffeinate"
export AIBOX_CAFFEINATE="$fake_caffeinate"

cat > "$ws/claude" <<'EOF'
#!/usr/bin/env bash
[[ -n "${AIBOX_ACTIVITY_FILE:-}" ]] || exit 11
touch "$AIBOX_ACTIVITY_FILE" || exit 12
# Leave the flag up long enough to cover a heavily loaded host's watcher tick.
sleep 1
rm -f "$AIBOX_ACTIVITY_FILE"
sleep 0.2
EOF
chmod +x "$ws/claude"
export PATH="$ws:$PATH"

cleanup() { rm -rf "$base"; }
trap cleanup EXIT
( cd "$ws" && HOME="$test_home" "$here/bin/claude" )
# caffeinate watches the pid; systemd-inhibit holds the assertion for as long
# as the command it wraps runs.
if [[ "$(uname -s)" == Darwin ]]; then
    grep -q '^start -i -w ' "$log"
else
    grep -q '^start --what=idle:sleep ' "$log"
fi
echo 'keep-awake bridge: OK'
