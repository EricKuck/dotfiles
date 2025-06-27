{
  config,
  lib,
  pkgs,
  ...
}:
let
  PORT = config.ports.prometheus-jellyfin-exporter;
in
{
  users = {
    users.jellyfin = {
      isSystemUser = true;
      group = "jellyfin";
    };

    groups.jellyfin = { };
  };

  sops.secrets.jellyfin_token.owner = "jellyfin";

  services.prometheus.scrapeConfigs = [
    {
      job_name = "jellyfin";
      scrape_interval = "10s";
      static_configs = [
        {
          targets = [ "localhost:${toString PORT}" ];
        }
      ];
    }
  ];

  systemd.services = {
    prometheus-jellyfin-exporter = {
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];
      serviceConfig = {
        User = "jellyfin";
        Restart = "always";
        RestartSec = "60s";
        ExecStart = "${lib.getExe pkgs.bash} -c '${lib.getExe pkgs.custom.prometheus-jellyfin-exporter} --jellyfin.address=http://localhost:${toString config.ports.jellyfin} --jellyfin.token=$(${pkgs.coreutils}/bin/cat ${config.sops.secrets.jellyfin_token.path}) --web.listen-address=:${toString PORT} --collector.activity'";
      };
    };
  };
}
