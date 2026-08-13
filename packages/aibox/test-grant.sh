#!/usr/bin/env bash
# Mechanism test for live directory grants: exercises the raw sandbox-
# extension functions (issue -> consume -> access) exactly the way the
# broker/launcher do, comparing the two issue flags.
#
# Run this OUTSIDE aibox, in a plain terminal: issuing an extension token
# requires an unsandboxed process (the broker runs outside the sandbox by
# design), and the test also needs sandbox-exec, which aibox's own profile
# blocks from nesting.
#
# Why it exists: `aibox allow <dir>` issues a token with
# SANDBOX_EXTENSION_DEFAULT and the sandboxed launcher consumes it. Two
# independent failures were found, both reproduced live:
#
#  1. SANDBOX_EXTENSION_CANONICAL (kernel realpath of the issued path)
#     expands firmlinks, so a token for /Users/eric/<dir> embeds
#     /System/Volumes/Data/Users/eric/<dir>; the sandboxed process accesses
#     the firmlink spelling, finds no matching extension, and the grant
#     silently never applies. sandbox.rs issues with DEFAULT.
#
#  2. A DEFAULT token embeds the target path verbatim, spaces included, and
#     the broker<->launcher CONSUME line used to carry it raw -- so the
#     launcher's first-space split truncated the token for any path with a
#     space and consumption failed before the kernel ever saw it. proto.rs
#     now carries tokens base64-encoded (no spaces in the alphabet).
#
# This script drives issue -> consume DIRECTLY, bypassing the transport, so
# it proves the kernel itself accepts the full token in each case -- the
# part that neither layer can fix if it fails.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
cargo build --manifest-path "$here/Cargo.toml" >/dev/null 2>&1
host="$here/target/debug/aibox-host"

work="$(mktemp -d "${TMPDIR:-/tmp}/aibox-grant-test.XXXXXX")"
trap 'rm -rf "$work"' EXIT

# The same profile a real session gets, for a throwaway workspace.
mkdir -p "$work/ws"
AIBOX_DENIAL_LOG="$work/denials.db" "$host" profile "$work/ws" > "$work/profile.sb"

cat > "$work/exttest.c" <<'EOF'
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <dirent.h>
#include <errno.h>
#include <stdint.h>
#include <sys/stat.h>
extern char *sandbox_extension_issue_file(const char *, const char *, uint32_t);
extern int64_t sandbox_extension_consume(const char *);
extern int32_t sandbox_extension_release(int64_t);
int main(int argc, char **argv) {
    if (argc < 2) return 2;
    if (!strcmp(argv[1], "issue")) {
        uint32_t fl = (uint32_t)strtoul(argv[2], NULL, 0);
        errno = 0;
        char *tok = sandbox_extension_issue_file("com.apple.app-sandbox.read-write", argv[3], fl);
        if (!tok) { printf("ISSUE-ERR errno=%d (%s)\n", errno, strerror(errno)); return 1; }
        printf("%s\n", tok);
        free(tok);
        return 0;
    }
    if (!strcmp(argv[1], "consume")) {
        int64_t h = sandbox_extension_consume(argv[2]);
        if (h < 0) { printf("CONSUME-ERR errno=%d (%s)\n", errno, strerror(errno)); return 1; }
        DIR *d = opendir(argv[3]);
        int e = errno;
        int n = 0;
        if (d) { struct dirent *de; while ((de = readdir(d))) n++; closedir(d); }
        printf("consume=ok access=%s entries=%d\n", d ? "GRANTED" : strerror(e), n);
        sandbox_extension_release(h);
        return d ? 0 : 1;
    }
    return 2;
}
EOF
cc -O0 -o "$work/exttest" "$work/exttest.c"

decode_path() {
    # Apple tokens are base64; the embedded path surfaces as 'path=...' or a
    # <string> in decoded form. Print what we can see.
    printf '%s' "$1" | base64 -D 2>/dev/null | strings \
        | grep -E '/[A-Za-z]' | head -1 || printf '(unparseable)'
}

# target, flags   -> issue (unsandboxed), consume (+access) inside the profile.
try() {
    local target="$1" flags="$2" label="$3"
    local tok
    printf '  flags=%s: ' "$label"
    tok="$("$work/exttest" issue "$flags" "$target")" || { echo "$tok"; return 1; }
    # Embed the canonical path the token carries.
    printf 'token path: %s\n' "$(decode_path "$tok")"
    printf '  -> sandboxed: '
    if sandbox-exec -f "$work/profile.sb" "$work/exttest" consume "$tok" "$target"; then
        echo "  PASS ($label)"
        return 0
    fi
    echo "  FAIL ($label)"
    return 1
}

# The primary case: the directory the user's live grant was denied on.
TARGET="${1:-$HOME/traces}"
plain=0; spaced=0; linked=0
if [[ -d "$TARGET" ]]; then plain=1; fi
space_dir="$HOME/aibox grant test dir"
if mkdir -p "$space_dir" 2>/dev/null; then spaced=1; fi
link="$HOME/aibox-grant-test-link"
if [[ -d "$TARGET" ]] && ln -sfn "$TARGET" "$link" 2>/dev/null; then
    # Mirror broker::allow: resolve symlinks before issue.
    linked=1
    LINK_TARGET="$(cd "$TARGET" && pwd -P)"
fi
cleanup_targets() { (( plain )) || true; (( spaced )) && rmdir "$space_dir" 2>/dev/null; (( linked )) && rm -f "$link"; }
trap 'cleanup_targets; rm -rf "$work"' EXIT

echo "profile: $work/profile.sb (workspace $work/ws)"
echo "target: $TARGET"
echo

if (( plain )); then
    echo "1) plain path, no symlink, no spaces:"
    try "$TARGET" 0 DEFAULT
    try "$TARGET" 1 CANONICAL
    echo
fi
if (( spaced )); then
    echo "2) path containing spaces ($space_dir):"
    try "$space_dir" 0 DEFAULT
    try "$space_dir" 1 CANONICAL
    echo
fi
if (( linked )); then
    echo "3) symlink path -> $LINK_TARGET (token issued for resolved target):"
    try "$LINK_TARGET" 0 DEFAULT
    try "$LINK_TARGET" 1 CANONICAL
    echo
fi
if (( ! plain && ! spaced )); then
    echo "no testable target: $TARGET does not exist and \$HOME is not writable here"
    echo "(run this script outside aibox, or pass an existing directory as argument)"
    exit 1
fi

echo "=== expectation ==="
echo "  DEFAULT grants access on every case (live allow works)."
echo "  CANONICAL fails at least on paths under /Users (firmlink mismatch) --"
echo "  that is the regression, and why sandbox.rs issues with DEFAULT."
echo "  A DEFAULT grant on the SPACED case (issue direct, no transport) also"
echo "  proves the kernel accepts the full token -- the old live failure was"
echo "  the launcher splitting the raw token at its embedded space, since"
echo "  fixed by base64 transport in proto.rs."