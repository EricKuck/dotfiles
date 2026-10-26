{
  writeShellApplication,
  git,
  openssh,
  tart,
}:

# Deploys the imessage-bridge nix-darwin config to the VM from IRLBuild:
# builds it here, copies the closure over and activates it. Also does
# nix-darwin's first activation on a fresh VM, which still has the Nix
# installer's setup.
writeShellApplication {
  name = "imessage-vm-deploy";
  runtimeInputs = [
    git
    openssh
    tart
  ];
  text = ''
    vm="''${1:-imessage-bridge}"
    flake="$(git rev-parse --show-toplevel)"
    host="eric@$(tart ip "$vm")"

    ssh_opts=(-o StrictHostKeyChecking=accept-new)
    export NIX_SSHOPTS="''${ssh_opts[*]}"
    # shellcheck disable=SC2029 # arguments are meant to expand here
    remote() { ssh "''${ssh_opts[@]}" "$host" "$@"; }

    # path: so the gitignored secrets are part of the build.
    system="$(nix build --no-link --print-out-paths "path:$flake#darwinConfigurations.imessage-bridge.system")"

    # Until nix-darwin's first activation, Nix only lives in the installer's
    # default profile.
    if remote test -x /run/current-system/sw/bin/nix-daemon; then
      remote_bin=/run/current-system/sw/bin
      first_run=false
    else
      remote_bin=/nix/var/nix/profiles/default/bin
      first_run=true
    fi

    if [ "$first_run" = true ]; then
      # The copy needs eric to be trusted by the daemon; nix-darwin manages
      # this after the first activation. Restart so the daemon picks it up.
      remote "grep -qs '^trusted-users.* eric' /etc/nix/nix.conf || echo 'trusted-users = root eric' | sudo tee -a /etc/nix/nix.conf >/dev/null
        sudo launchctl kickstart -k system/org.nixos.nix-daemon"
      sleep 2
    fi

    # Paths built here aren't signed; the guest accepts them unchecked
    # because it trusts eric.
    nix copy --no-check-sigs --to "ssh-ng://$host?remote-program=$remote_bin/nix-daemon" "$system"

    if [ "$first_run" = true ]; then
      # nix-darwin refuses to replace /etc files it didn't write.
      # shellcheck disable=SC2016 # runs on the VM
      remote 'for f in /etc/nix/nix.conf /etc/bashrc /etc/zshrc /etc/zshenv; do
        if [ -f "$f" ] && [ ! -L "$f" ]; then sudo mv "$f" "$f.before-nix-darwin"; fi
      done'
    fi

    remote sudo "$system/sw/bin/nix-env" -p /nix/var/nix/profiles/system --set "$system"
    remote sudo "$system/activate"
  '';
}
