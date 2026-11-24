{
  lib,
  config,
  ...
}:

let
  inherit (lib) mkEnableOption mkIf;
  cfg = config.custom.environments.server;
in
{
  options.custom.environments.server = {
    enable = mkEnableOption "server";
  };

  config = mkIf cfg.enable {
    custom.programs.nh.enable = true;
    custom.programs.rex.enable = true;

    power = {
      sleep = {
        computer = "never";
        harddisk = "never";
      };
      restartAfterFreeze = true;
    };

    system.activationScripts.postActivation.text = ''
      echo >&2 "disabling sleep..."
      pmset -a sleep 0 disksleep 0 standby 0 powernap 0 ttyskeepawake 1 || true
      pmset -a disablesleep 1 || true
    '';
  };
}
