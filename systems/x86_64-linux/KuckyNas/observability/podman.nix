{
  config,
  lib,
  pkgs,
  ...
}:
let
  PORT = config.ports.prometheus-podman-exporter;
in
{
  services.prometheus.scrapeConfigs = [
    {
      job_name = "podman";
      scrape_interval = "10s";
      static_configs = [
        {
          targets = [ "localhost:${toString PORT}" ];
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
        ExecStart = "${lib.getExe pkgs.custom.prometheus-podman-exporter} --web.listen-address localhost:${toString PORT} --collector.image";
      };
    };
  };
}
