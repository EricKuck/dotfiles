{
  lib,
  pkgs,
  inputs,
  system,
  config,
  ...
}:

let
  inherit (lib) mkEnableOption mkIf;
  cfg = config.custom.cli-apps.zellij;
in
{
  options.custom.cli-apps.zellij = {
    enable = mkEnableOption "zellij";
  };

  config = mkIf cfg.enable {
    home = {
      packages = with pkgs; [
        zellij
        (lib.custom.scripts.zj pkgs)
        (lib.custom.scripts.zellij-env pkgs)
      ];

      shellAliases = {
        zellij = "zellij-env";
      };
    };

    programs.fish.interactiveShellInit = ''
      if ! test $ZELLIJ && test $KITTY_WINDOW_ID
        # Select or start a zellij session
        zj --from-init

        # Kill instance when zellij exits, unless it was ctrl-c'd
        if test $status -ne 130
          kill $fish_pid
        end
      end
    '';

    xdg.configFile = {
      "zellij/config.kdl".source = ../configs/zellij/config.kdl;
    };
  };
}
