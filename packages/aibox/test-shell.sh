#!/usr/bin/env bash
# Proves aibox shell lets Fish persist its host config and history while keeping
# all other home directories outside the profile.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
cargo build --manifest-path "$here/Cargo.toml" >/dev/null 2>&1
host="$here/target/debug/aibox-host"

base="$HOME/aibox-shell-smoke"
ws="$base/ws"
test_home="$base/home"
export AIBOX_STATE_ROOT="$base/state"
rm -rf "$base"
cleanup() { rm -rf "$base"; }
trap cleanup EXIT
mkdir -p "$ws" "$test_home/.config/fish" "$test_home/.local/share/fish" "$test_home/.cargo/bin" "$test_home/.rustup"
printf 'set -gx CARGO_HOME "%s/.cargo"\n' "$test_home" > "$test_home/.cargo/env.fish"
printf 'cargo-tool\n' > "$test_home/.cargo/bin/tool"
printf 'secret-token\n' > "$test_home/.cargo/credentials.toml"
printf 'default_toolchain = "stable"\n' > "$test_home/.rustup/settings.toml"
printf 'secret-token\n' > "$test_home/.rustup/credentials.toml"
HOME="$test_home" "$host" profile "$ws" > "$base/policy"
# The two backends spell the same policy differently: Seatbelt allows a subpath
# and denies a deeper one, bubblewrap binds a tree and masks a path inside it.
if [[ "$(uname -s)" == Darwin ]]; then
    grep -Fxq '(debug deny)' "$base/policy"
    grep -Fq "(subpath \"$test_home/.rustup\")" "$base/policy"
    grep -Fq "(subpath \"$test_home/.rustup/credentials.toml\")" "$base/policy"
else
    grep -Fxq "$test_home/.rustup" "$base/policy"
    grep -Fxq "$test_home/.rustup/credentials.toml" "$base/policy"
    grep -Fxq '/dev/null' "$base/policy"
fi

fake_fish="$ws/fish"
cat > "$fake_fish" <<'EOF'
#!/usr/bin/env bash
printf 'universal=1\n' > "$HOME/.config/fish/fish_variables"
printf 'history entry\n' > "$HOME/.local/share/fish/fish_history"
cat "$HOME/.cargo/env.fish" > "$PWD/cargo-env"
cat "$HOME/.cargo/bin/tool" > "$PWD/cargo-tool"
! cat "$HOME/.cargo/credentials.toml" >/dev/null 2>&1
cat "$HOME/.rustup/settings.toml" > "$PWD/rustup-settings"
! cat "$HOME/.rustup/credentials.toml" >/dev/null 2>&1
printf '%s\n' "${XDG_CONFIG_HOME:-}" > "$PWD/xdg-config-home"
printf '%s\n' "${AIBOX_SHELL:-}" > "$PWD/aibox-shell"
EOF
chmod +x "$fake_fish"

( cd "$ws" && env -u XDG_CONFIG_HOME -u XDG_DATA_HOME HOME="$test_home" SHELL="$fake_fish" "$here/bin/aibox" shell )
grep -qx 'universal=1' "$test_home/.config/fish/fish_variables"
grep -qx 'history entry' "$test_home/.local/share/fish/fish_history"
grep -qx "set -gx CARGO_HOME \"$test_home/.cargo\"" "$ws/cargo-env"
grep -qx 'cargo-tool' "$ws/cargo-tool"
grep -qx 'default_toolchain = "stable"' "$ws/rustup-settings"
[[ "$(<"$ws/xdg-config-home")" == "" ]]
grep -qx '1' "$ws/aibox-shell"
echo 'shared Fish config, history, rustup access, and shell marker: OK'
