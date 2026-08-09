#!/usr/bin/env bash
# Proves that aibox detects a linked worktree and grants only its external
# common .git directory, allowing normal Git commands inside the sandbox.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
cargo build --manifest-path "$here/Cargo.toml" >/dev/null 2>&1

base="$HOME/aibox-worktree-smoke"
main="$base/main"
ws="$base/ws"
export AIBOX_STATE_ROOT="$HOME/.aibox/test-worktree-state"
rm -rf "$base" "$AIBOX_STATE_ROOT"
cleanup() { rm -rf "$base" "$AIBOX_STATE_ROOT"; }
trap cleanup EXIT

mkdir -p "$main"
git -C "$main" init -q
git -C "$main" config user.name aibox-test
git -C "$main" config user.email aibox-test@example.invalid
printf 'tracked\n' > "$main/file"
git -C "$main" add file
git -C "$main" commit -qm initial
git -C "$main" worktree add -q "$ws"

cat > "$ws/claude" <<'EOF'
#!/bin/bash
if GIT_CONFIG_GLOBAL=/dev/null git -C "$PWD" status --porcelain >/dev/null 2>&1; then
    printf 'git-ok\n' > "$PWD/result"
else
    printf 'git-failed\n' > "$PWD/result"
fi
EOF
chmod +x "$ws/claude"
export PATH="$ws:$PATH"

( cd "$ws" && "$here/bin/claude" )
grep -qx 'git-ok' "$ws/result"
echo 'linked worktree Git access: OK'
