{ lib }: rec {
  scripts = {
    kopia-backup = pkgs:
      pkgs.writeShellScript "kopia-backup" ''
        set -eou pipefail

        backups=(
          "/home/eric/.config"
          "/kuckyjar/container"
        )

        for dir in "''${backups[@]}"; do
          ${lib.getExe' pkgs.kopia "kopia"} snapshot create "$dir"
        done
      '';
  };
}
