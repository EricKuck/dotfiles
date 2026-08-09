#!/usr/bin/env bash
# Proves the two filesystem facts the Supacode integration rests on: the
# terminal's own app bundle reads (its CLI, its frameworks, and the terminfo
# entry for $TERM all live in there) but does not write, and /dev lists so
# devname(3) can name the tty the agent presence hooks signal on.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
cargo build --manifest-path "$here/Cargo.toml" >/dev/null 2>&1

base="$HOME/aibox-supacode-smoke"
ws="$base/ws"
test_home="$base/home"
bundle="$test_home/Applications/supacode.app"
export AIBOX_STATE_ROOT="$base/state"
rm -rf "$base"
cleanup() { rm -rf "$base"; }
trap cleanup EXIT
mkdir -p "$ws" "$bundle/Contents/Frameworks" "$bundle/Contents/Resources/terminfo/x"
printf 'framework\n' > "$bundle/Contents/Frameworks/Sparkle"
printf 'terminfo\n' > "$bundle/Contents/Resources/terminfo/x/xterm-ghostty"

fake_shell="$ws/shell"
cat > "$fake_shell" <<'EOF'
#!/bin/bash
app="$HOME/Applications/supacode.app"
cat "$app/Contents/Frameworks/Sparkle" > "$PWD/framework"
cat "$app/Contents/Resources/terminfo/x/xterm-ghostty" > "$PWD/terminfo"
! : > "$app/Contents/Frameworks/injected" 2>/dev/null
ls /dev > "$PWD/dev-listing"
EOF
chmod +x "$fake_shell"

( cd "$ws" && env HOME="$test_home" SHELL="$fake_shell" "$here/bin/aibox" shell )
grep -qx 'framework' "$ws/framework"
grep -qx 'terminfo' "$ws/terminfo"
[[ ! -e "$bundle/Contents/Frameworks/injected" ]]
grep -qx 'null' "$ws/dev-listing"
echo 'terminal app bundle read-only access and /dev listing: OK'
