{
  config,
  lib,
  pkgs,
  ...
}:
let
  PORT = config.ports.prometheus-quadlet-exporter;
in
{
  services.prometheus.scrapeConfigs = [
    {
      job_name = "quadlet";
      scrape_interval = "10s";
      static_configs = [
        {
          targets = [ "localhost:${toString PORT}" ];
        }
      ];
    }
  ];

  home-manager.users.eric.systemd.user.services = {
    prometheus-quadlet-exporter = {
      Unit.After = [ "network.target" ];
      Service.ExecStart = "${lib.getExe pkgs.custom.prometheus-quadlet-exporter} --port ${toString PORT}";
      Install.WantedBy = [ "default.target" ];
    };
  };
}
