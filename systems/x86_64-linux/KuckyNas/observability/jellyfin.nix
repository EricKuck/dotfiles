{
  config,
  lib,
  pkgs,
  ...
}:
{
  services.custom.prometheus-exporters.jellyfin = {
    enable = true;
    port = config.ports.prometheus-jellyfin-exporter;
    systemd.execStart = "${lib.getExe pkgs.bash} -c '${lib.getExe pkgs.custom.prometheus-jellyfin-exporter} --jellyfin.address=http://localhost:${toString config.ports.jellyfin} --jellyfin.token=$(${pkgs.coreutils}/bin/cat ${config.sops.secrets.jellyfin_token.path}) --web.listen-address=:${toString config.ports.prometheus-jellyfin-exporter} --collector.activity'";
  };

  sops.secrets.jellyfin_token.owner =
    config.services.custom.prometheus-exporters.jellyfin.systemd.user;
}
