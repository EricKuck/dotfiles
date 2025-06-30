{
  config,
  lib,
  pkgs,
  ...
}:
let
  port = config.ports.prometheus-quadlet-exporter;
in
{
  services.prometheus.scrapeConfigs = [
    {
      job_name = "quadlet";
      scrape_interval = "10s";
      static_configs = [
        {
          targets = [ "localhost:${toString port}" ];
        }
      ];
    }
  ];

  home-manager.users.eric.systemd.user.services = {
    prometheus-quadlet-exporter = {
      Unit.After = [ "network.target" ];
      Service.ExecStart = "${lib.getExe pkgs.custom.prometheus-quadlet-exporter} --port ${toString port}";
      Install.WantedBy = [ "default.target" ];
    };
  };
}
