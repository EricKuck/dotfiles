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
  cfg = config.custom.environments.backups;
in
{
  options.custom.environments.backups = {
    enable = mkEnableOption "backups";
  };

  config = mkIf cfg.enable {
    environment.systemPackages = with pkgs; [ kopia ];

    launchd = {
      user = {
        agents = {
          kopia-backup = {
            command = "${lib.getExe' pkgs.kopia "kopia"} snapshot create --all";
            serviceConfig = {
              StartInterval = 3600;
            };
          };

          kopia-server = {
            command = "${lib.getExe' pkgs.kopia "kopia"} server start --insecure --without-password";
            serviceConfig = {
              KeepAlive = true;
              RunAtLoad = true;
            };
          };
        };
      };
    };
  };
}
