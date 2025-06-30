{
  config,
  lib,
  pkgs,
  ...
}:
let
  port = config.ports.prometheus-podman-exporter;
  name = "podman-exporter";
in
{
  users = {
    users."${name}" = {
      isSystemUser = true;
      group = name;
      extraGroups = [ "podman" ];
    };

    groups."${name}" = { };
  };

  services.prometheus.scrapeConfigs = [
    {
      job_name = "podman";
      scrape_interval = "10s";
      static_configs = [
        {
          targets = [ "localhost:${toString port}" ];
        }
      ];
    }
  ];

  systemd.services = {
    prometheus-podman-exporter = {
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];
      serviceConfig = {
        Restart = "always";
        RestartSec = "60s";
        User = name;
        ExecStart = "${lib.getExe pkgs.custom.prometheus-podman-exporter} --web.listen-address localhost:${toString port} --collector.image";
      };
    };
  };
}
