{ lib }:
rec {
  scripts = {
    activate-btt =
      pkgs:
      pkgs.writeShellScriptBin "activate-btt" ''
        #!/usr/bin/env bash
        set -e
        license=$(sudo cat /run/secrets/btt_license)
        open "btt://license/$license"
      '';

    activate-istat =
      pkgs:
      pkgs.writeShellScriptBin "activate-istat" ''
        #!/usr/bin/env bash
        set -e
        license=$(sudo cat /run/secrets/istat_menus_license)
        printf "iStat Menus doesn't have an activation URL. Enter this in the license menu:\n$license"
      '';
  };
}
