{
  lib,
  pkgs,
  inputs,
  config,
  osConfig ? { },
  ...
}:
with lib.custom;
{
  imports = [
    ./quadlets
  ];

  custom = {
    environments.server = {
      enable = true;
      podman.enable = true;
    };
  };

  systemd.user = {
    services = {
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
    };
  };

  home.packages = with pkgs; [
    ffmpeg
    sacad
  ];
}
