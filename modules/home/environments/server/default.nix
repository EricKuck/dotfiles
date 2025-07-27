{
  config,
  osConfig,
  lib,
  pkgs,
  inputs,
  system,
  ...
}:

let
  inherit (lib) mkEnableOption mkIf;
  cfg = config.custom.environments.server;
in
{
  options.custom.environments.server = {
    enable = mkEnableOption "server";

    podman = {
      enable = mkEnableOption "podman";
    };
  };

  config = mkIf cfg.enable {
    custom = {
      cli-apps = {
        common.enable = true;
      };
    };

    home.packages =
      with pkgs;
      [
        kopia
        iotop
        inputs.ghostty.packages."${system}".default
      ]
      ++ lib.optional cfg.podman.enable pkgs.podman-compose;

    systemd.user = {
      # Ensure the systemd services are (re)started on config change
      startServices = "sd-switch";

      services = {
        dns-ready = {
          Unit = {
            Description = "Wait for DNS to come up";
            After = [ "network-online.target" ];
          };
          Service = {
            Type = "oneshot";
            ExecStart = "${lib.getExe pkgs.bash} -c 'until ${lib.getExe' pkgs.host "host"} google.com; do ${pkgs.coreutils}/bin/sleep 1; done'";
          };
          Install = {
            WantedBy = [ "default.target" ];
          };
        };

        kopia-backup-all = {
          Unit = {
            Description = "Kopia backup";
            After = [ "network.target" ];
          };
          Service = {
            Type = "oneshot";
            TimeoutSec = 1320;
            ExecStart = "${osConfig.security.wrapperDir}/${osConfig.security.wrappers.kopia.program} snapshot create --all";
          };
        };

        kopia-server = {
          Unit = {
            Description = "Start the kopia web ui server";
            After = [ "dns-ready.service" ];
          };
          Service = {
            Type = "simple";
            ExecStart = "${osConfig.security.wrapperDir}/${osConfig.security.wrappers.kopia.program} server start --disable-csrf-token-checks --insecure --address=0.0.0.0:51515 --without-password";
          };
          Install = {
            WantedBy = [ "default.target" ];
          };
        };
      };

      timers = {
        kopia-backup-all = {
          Unit.Description = "Kopia backup schedule";
          Timer = {
            Unit = "kopia-backup-all.service";
            OnBootSec = "1h";
            OnUnitActiveSec = "1h";
          };
          Install.WantedBy = [ "timers.target" ];
        };
      };
    };

    services.podman = lib.mkIf cfg.podman.enable {
      enable = true;
      autoUpdate = {
        enable = true;
        onCalendar = "*-*-* 03:00:00";
      };
    };
  };
}
