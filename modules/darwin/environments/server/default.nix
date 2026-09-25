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

    power = {
      sleep = {
        computer = "never";
        harddisk = "never";
      };
      restartAfterFreeze = true;
    };
  };
}
