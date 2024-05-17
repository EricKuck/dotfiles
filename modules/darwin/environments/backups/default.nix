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
              StartCalendarInterval = [
                { Hour = 0; }
                { Hour = 1; }
                { Hour = 2; }
                { Hour = 3; }
                { Hour = 4; }
                { Hour = 5; }
                { Hour = 6; }
                { Hour = 7; }
                { Hour = 8; }
                { Hour = 9; }
                { Hour = 10; }
                { Hour = 11; }
                { Hour = 12; }
                { Hour = 13; }
                { Hour = 14; }
                { Hour = 15; }
                { Hour = 16; }
                { Hour = 17; }
                { Hour = 18; }
                { Hour = 19; }
                { Hour = 20; }
                { Hour = 21; }
                { Hour = 22; }
                { Hour = 23; }
              ];
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
