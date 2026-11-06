#!/bin/sh
export PATH="/run/wrappers/bin:$HOME/.nix-profile/bin:/etc/profiles/per-user/$USER/bin:/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:$PATH"

st() {
  printf '\033]7501;state=%s:app=nix-rebuild%s:msg=%s\033\134' "$1" "$2" \
    "$(printf '%s' "$3" | base64 | tr -d '\n')"
}
fail() {
  st error "" "$1"
  printf '\n\033[31m%s\033[0m\n' "$1"
  exit 1
}

if [ "$(uname)" = Darwin ]; then
  kind=darwin
  default_dir=$HOME/.config/nix
else
  kind=os
  default_dir=$HOME/.config/nixos
fi
export NH_FLAKE="${NH_FLAKE:-path:$default_dir}"
dir=${NH_FLAKE#path:}

if [ -d "$dir/.git" ]; then
  st working "" "Fetching"
  git -C "$dir" pull --ff-only || fail "git pull failed"
fi

if ! sudo -n true 2>/dev/null; then
  st blocked ":kind=auth" "sudo password needed"
  sudo -v || fail "sudo failed"
fi
# nh only sudoes at activation, which can be past sudo's timeout on a long build.
while sleep 60; do sudo -n -v 2>/dev/null; done &
keepalive=$!
trap 'kill $keepalive 2>/dev/null' EXIT

st working "" "Rebuilding"
nh "$kind" switch || fail "Rebuild failed"
st "done" "" "Rebuilt"
