#!/usr/bin/env bash
# Proves the enclosing-repository rule: the repo the workspace belongs to has
# its .git and .claude readable and writable even when they sit in a parent of
# the workspace, while the repository's own files, its parent's listing, its
# sibling secrets, and unrelated repositories elsewhere on disk stay denied.
#
# Run me from a normal (unsandboxed) terminal: `bash test-git.sh`.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
cargo build --manifest-path "$here/Cargo.toml" >/dev/null 2>&1

base="$HOME/aibox-git-smoke"
ws="$base/ws"
ext="$HOME/aibox-git-smoke-ext"
export AIBOX_STATE_ROOT="$base/state"
rm -rf "$base" "$ext"
cleanup() { rm -rf "$base" "$ext"; }
trap cleanup EXIT

# A repository whose root is a PARENT of the workspace -- e.g. a workspace at
# ~/.config/nix/packages/foo inside the ~/.config/nix repo. Every git command
# in the workspace resolves this .git, and the harness reads project settings
# from the .claude beside it; without the rule both spam denials.
mkdir -p "$base"
git -C "$base" init -q
git -C "$base" config user.name aibox-test
git -C "$base" config user.email aibox-test@example.invalid
printf 'tracked\n' > "$base/file"
git -C "$base" add file
git -C "$base" commit -qm initial
printf 'secret-sibling\n' > "$base/secret-file"
mkdir -p "$base/.claude"
printf '{}\n' > "$base/.claude/settings.local.json"
mkdir -p "$ws"

# A completely unrelated repo elsewhere on disk. The workspace does not belong
# to it, so it gets nothing -- not even its .git.
mkdir -p "$ext"
git -C "$ext" init -q
git -C "$ext" config user.name aibox-test
git -C "$ext" config user.email aibox-test@example.invalid
printf 'tracked\n' > "$ext/file"
git -C "$ext" add file
git -C "$ext" commit -qm initial

cat > "$ws/claude" <<EOF
#!/bin/bash
mark() { printf 'ok\n' > "$ws/result-\$1"; }

# A workspace nested in a bigger repo can run git (its .git is in a parent).
if GIT_CONFIG_GLOBAL=/dev/null git -C "$ws" status --porcelain >/dev/null 2>&1 \
   && GIT_CONFIG_GLOBAL=/dev/null git -C "$ws" branch smoke >/dev/null 2>&1; then
    mark nested-git-ok
fi
if cat "$base/.git/config" >/dev/null 2>&1; then
    mark gitdir-readable
fi

# The repo root's .claude rides the same rule, read and write.
if cat "$base/.claude/settings.local.json" >/dev/null 2>&1 \
   && printf '{}\n' > "$base/.claude/written" 2>/dev/null; then
    mark claude-rw
fi

# The rule grants only those two directories: the repo's own files, the
# parent's listing, and a sibling secret all stay denied.
if cat "$base/file" >/dev/null 2>&1; then mark parent-exposed; fi
if ls "$base" >/dev/null 2>&1; then mark listing-exposed; fi
if cat "$base/secret-file" >/dev/null 2>&1; then mark sibling-exposed; fi

# An unrelated repository the workspace is not part of gets nothing.
if cat "$ext/.git/config" >/dev/null 2>&1; then mark ext-git-exposed; fi
EOF
chmod +x "$ws/claude"
export PATH="$ws:$PATH"

( cd "$ws" && "$here/bin/claude" )
grep -qx 'ok' "$ws/result-nested-git-ok"      || { echo "FAIL: git could not use the parent repo"; exit 1; }
grep -qx 'ok' "$ws/result-gitdir-readable"    || { echo "FAIL: .git contents not readable"; exit 1; }
grep -qx 'ok' "$ws/result-claude-rw"          || { echo "FAIL: repo-root .claude not read-write"; exit 1; }
[[ ! -e "$ws/result-parent-exposed" ]]        || { echo "FAIL: parent repo files were readable"; exit 1; }
[[ ! -e "$ws/result-listing-exposed" ]]       || { echo "FAIL: parent directory was listable"; exit 1; }
[[ ! -e "$ws/result-sibling-exposed" ]]       || { echo "FAIL: sibling secret was readable"; exit 1; }
[[ ! -e "$ws/result-ext-git-exposed" ]]       || { echo "FAIL: an unrelated repo's .git was readable"; exit 1; }
echo 'enclosing-repository access with parent isolation: OK'
