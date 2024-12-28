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
  custom = {
    cli-apps = {
      common.enable = true;
    };
  };

  home.packages = with pkgs; [
    custom.podman-compose
    kopia
    podman-tui
    iotop
    inputs.ghostty.packages.x86_64-linux.default
  ];

  systemd.user = {
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
          Description = "Sync photos from iCloud & Google Photos, sync with Immich";
          After = [ "network.target" ];
        };
        Service = {
          Type = "oneshot";
          TimeoutSec = 1200;
          ExecStart = pkgs.writeShellScript "sync-cloud-photos" ''
            set -eou pipefail

            ${lib.getExe pkgs.unstable.icloudpd} --directory /kuckyjar/media/Photos/eric/icloud --username $(${pkgs.coreutils}/bin/cat ${osConfig.sops.secrets.eric_icloud_username.path}) --until-found 20
            ${lib.getExe pkgs.unstable.gphotos-sync} --port 9482 /kuckyjar/media/Photos/eric/gphotos/
            ${lib.getExe pkgs.unstable.immich-go} -no-ui upload /kuckyjar/media/Photos/eric
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

      podman-stop-all = {
        Unit = {
          Description = "Stop all podman containers";
          After = [ "network-online.target" ];
        };
        Service = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = "/run/current-system/sw/bin/true";
          ExecStop = pkgs.writeShellScript "_podman-stop-all" ''
            set -x
            ${lib.getExe pkgs.podman} stop $(${lib.getExe pkgs.podman} ps -a -q);
          '';
        };
        Install = {
          WantedBy = [ "default.target" ];
        };
      };

      podman-start-all = {
        Unit = {
          Description = "Start all podman-compose stacks marked as autostart";
          After = [
            "podman-stop-all.service"
            "network-online.target"
          ];
        };
        Service = {
          Type = "forking";
          TimeoutSec = 300;
          Environment = "PATH=/run/wrappers/bin:/nix/var/nix/profiles/default/bin:/run/current-system/sw/bin";
          ExecStart = "${lib.getExe pkgs.custom.podman-compose} start-all --dir='/kuckyjar/container/stacks/'";
        };
        Install = {
          WantedBy = [ "default.target" ];
        };
      };
    };

    timers = {
      sync-cloud-photos = {
        Unit.Description = "Sync photos from iCloud & Google Photos, sync with Immich";
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
}
