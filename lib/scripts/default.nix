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

    zellij =
      pkgs:
      pkgs.writeShellScriptBin "zj" ''
        #!/usr/bin/env bash

        if [ -n "$ZELLIJ" ]; then
          echo "Already in a zellij session, aborting"
          exit 1
        fi

        new_session="New Session"

        sessions=$(zellij list-sessions)
        sessions+=("$new_session")

        session_name="$(printf "%s\n" "''${sessions[@]}" \
        	| fzf --ansi --layout reverse --height ~100% --prompt "Session: ")"

        echo $session_name

        if [ "$session_name" == "$new_session" ]; then
          zellij
        elif [ -n "$session_name" ]; then
          session_name=$(echo "$session_name" | awk '{print $1}')
          echo "Switching to $session_name"
          zellij attach "$session_name"
        fi
      '';
  };
}
