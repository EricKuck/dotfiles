{
  inputs,
  lib,
  pkgs,
  config,
  osConfig ? { },
  ...
}:
with lib.custom;
{
  imports = [
    ./containers
  ];

  custom = {
    cli-apps = {
      common.enable = true;
    };
  };

  home.packages = with pkgs; [
    podman-compose
    kopia
    iotop
    inputs.ghostty.packages.x86_64-linux.default
  ];

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
          ExecStart = "${lib.getExe pkgs.bash} -c 'until ${lib.getExe' pkgs.host "host"} google.com; do sleep 1; done'";
        };
        Install = {
          WantedBy = [ "default.target" ];
        };
      };

      sync-cloud-photos = {
        Unit = {
          Description = "Sync photos from iCloud, sync with Immich";
          After = [ "network.target" ];
        };
        Service = {
          Type = "oneshot";
          TimeoutSec = 1200;
          ExecStart = pkgs.writeShellScript "sync-cloud-photos" ''
            set -eou pipefail

            ${lib.getExe pkgs.unstable.icloudpd} --directory /kuckyjar/media/Photos/eric/icloud --username $(${pkgs.coreutils}/bin/cat ${osConfig.sops.secrets.eric_icloud_username.path}) --until-found 20
            ${lib.getExe pkgs.unstable.immich-go} upload from-folder /kuckyjar/media/Photos/eric --no-ui --server http://localhost:${toString osConfig.ports.immich} --api-key $(${pkgs.coreutils}/bin/cat ${osConfig.sops.secrets.immich_api_key.path})
          '';
        };
      };

      kopia-backup-all = {
        Unit = {
          Description = "Kopia backup";
          After = [ "network.target" ];
        };
        Service = {
          Type = "oneshot";
          TimeoutSec = 900;
          ExecStart = "${osConfig.security.wrapperDir}/${osConfig.security.wrappers.kopia-backup-all.program}";
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
      sync-cloud-photos = {
        Unit.Description = "Sync photos from iCloud, sync with Immich";
        Timer = {
          Unit = "sync-cloud-photos.service";
          OnBootSec = "1h";
          OnUnitActiveSec = "1h";
        };
        Install.WantedBy = [ "timers.target" ];
      };

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

  services.podman = {
    enable = true;
    autoUpdate = {
      enable = true;
      onCalendar = "*-*-* 03:00:00";
    };
  };
}
