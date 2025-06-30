{
  config,
  lib,
  pkgs,
  ...
}:
let
  port = config.ports.prometheus-jellyfin-exporter;
  name = "jellyfin-exporter";
in
{
  users = {
    users."${name}" = {
      isSystemUser = true;
      group = name;
    };

    groups."${name}" = { };
  };

  sops.secrets.jellyfin_token.owner = name;

  services.prometheus.scrapeConfigs = [
    {
      job_name = "jellyfin";
      scrape_interval = "10s";
      static_configs = [
        {
          targets = [ "localhost:${toString port}" ];
        }
      ];
    }
  ];

  systemd.services = {
    prometheus-jellyfin-exporter = {
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];
      serviceConfig = {
        User = name;
        Restart = "always";
        RestartSec = "60s";
        ExecStart = "${lib.getExe pkgs.bash} -c '${lib.getExe pkgs.custom.prometheus-jellyfin-exporter} --jellyfin.address=http://localhost:${toString config.ports.jellyfin} --jellyfin.token=$(${pkgs.coreutils}/bin/cat ${config.sops.secrets.jellyfin_token.path}) --web.listen-address=:${toString port} --collector.activity'";
      };
    };
  };
}
