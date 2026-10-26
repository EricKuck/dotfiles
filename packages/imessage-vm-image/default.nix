{
  lib,
  writeShellApplication,
  writeText,
  tart,
  packer,
  python3,
  ssh-to-age,
  openssh,
}:

# Builds the macOS VM that hosts iMessage for the Matrix bridge (the
# imessage-bridge host): a Cirrus Labs vanilla image with SIP disabled (needed
# by the BlueBubbles Private API), the admin account replaced by eric
# (auto-login, key-only SSH) and Nix installed. nix-darwin takes over from
# there.
#
# This is deliberately a one-off script rather than part of the system build:
# the VM's disk is persistent state (iMessage registration, Messages history),
# so it is never rebuilt on a flake update, and macOS is updated in place.
let
  # Every key there may SSH in as eric; password logins are disabled.
  authorizedKeys = writeText "imessage-vm-authorized-keys" (
    lib.concatMapStrings builtins.readFile (
      lib.fileset.toList (
        lib.fileset.fileFilter (file: file.hasExt "pub") ../../systems/aarch64-darwin/imessage-bridge/keys
      )
    )
  );
in
writeShellApplication {
  name = "imessage-vm-image";
  runtimeInputs = [
    tart
    packer
    python3
    ssh-to-age
    openssh
  ];
  text = ''
    # macOS 15: BlueBubbles' Private API doesn't work on 26 yet.
    base_image="ghcr.io/cirruslabs/macos-sequoia-vanilla:15.7.7"

    if [ $# -gt 1 ]; then
      echo "usage: imessage-vm-image [vm name]" >&2
      exit 1
    fi
    vm_name="''${1:-imessage-bridge}"

    if tart get "$vm_name" >/dev/null 2>&1; then
      echo "VM '$vm_name' already exists; delete it first if you really want a fresh one" >&2
      echo "(that loses its iMessage registration)." >&2
      exit 1
    fi

    # eric's login password: used for auto-login (which also unlocks the
    # keychain Messages needs) and whenever macOS asks in the GUI.
    read -rsp "Password for eric in the VM: " PKR_VAR_password; echo
    read -rsp "Again: " password_confirm; echo
    if [ "$PKR_VAR_password" != "$password_confirm" ]; then
      echo "Passwords don't match." >&2
      exit 1
    fi
    export PKR_VAR_password

    # /etc/kcpassword is the password XORed with Apple's fixed key, padded
    # with zeros to a multiple of the key length.
    PKR_VAR_kcpassword_hex="$(printf %s "$PKR_VAR_password" | python3 -c '
    import sys
    key = [0x7D, 0x89, 0x52, 0x23, 0xD2, 0xBC, 0xDD, 0xEA, 0xA3, 0xB9, 0x1F]
    pw = list(sys.stdin.buffer.read())
    pw += [0] * (-len(pw) % len(key))
    print(bytes(b ^ key[i % len(key)] for i, b in enumerate(pw)).hex())
    ')"
    export PKR_VAR_kcpassword_hex

    out_dir="$(mktemp -d)"
    trap 'rm -rf "$out_dir"' EXIT

    # Lets the finalize build log in as eric without the password; it removes
    # the key from the VM again.
    ssh-keygen -q -t ed25519 -N "" -C imessage-vm-build -f "$out_dir/build_key"

    for template in ${./disable-sip.pkr.hcl} ${./provision.pkr.hcl} ${./finalize.pkr.hcl}; do
      packer init "$template"
    done

    tart clone "$base_image" "$vm_name"
    tart set "$vm_name" --cpu 4 --memory 8192

    packer build -var "vm_name=$vm_name" ${./disable-sip.pkr.hcl}
    packer build -var "vm_name=$vm_name" -var "authorized_keys=$(cat ${authorizedKeys} "$out_dir/build_key.pub")" ${./provision.pkr.hcl}
    packer build -var "vm_name=$vm_name" -var "output_dir=$out_dir" -var "ssh_key=$out_dir/build_key" ${./finalize.pkr.hcl}

    echo
    echo "Built '$vm_name'. Its sops age recipient (for .sops.yaml):"
    ssh-to-age < "$out_dir/id_ed25519_sops.pub"
  '';
}
