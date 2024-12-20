{ lib }:
rec {
  scripts = {
    kopia-backup =
      pkgs:
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

    zj =
      pkgs:
      pkgs.writeShellScriptBin "zj" ''
        #!/usr/bin/env bash
        if [ -n "$ZELLIJ" ]; then
          if [ "$1" == "--from-init" ]; then
            exit 0
          else
            echo "Already in a zellij session, aborting"
            exit 1
          fi
        fi

        sessions=$(${lib.getExe pkgs.zellij} list-sessions)

        if [ $? -eq 1 ]; then
          zellij-env
          exit 0
        fi

        new_session="New Session"
        sessions+=("$new_session")

        set -e
        session_name="$(printf "%s\n" "''${sessions[@]}" \
        	| fzf --ansi --layout reverse --height ~100% --prompt "Session: ")"

        if [ "$session_name" == "$new_session" ]; then
          zellij-env
        elif [ -n "$session_name" ]; then
          session_name=$(echo "$session_name" | awk '{print $1}')
          echo "Switching to $session_name"
          zellij-env attach "$session_name"
        fi
      '';

    zellij-env =
      pkgs:
      pkgs.writeShellScriptBin "zellij-env" ''
        #!/usr/bin/env bash
        if [ -z "$ZELLIJ" ]; then
          kitty @ --password="a" set-user-vars ZELLIJ=1
        fi
        ${lib.getExe pkgs.zellij} "$@"
        if [ -z "$ZELLIJ" ]; then
          kitty @ --password="a" set-user-vars ZELLIJ=0
        fi
      '';

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
