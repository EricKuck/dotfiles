{ config, pkgs, ... }:
let
  port = config.ports.prometheus-user-systemd-exporter;
in
{
  services.prometheus.scrapeConfigs = [
    {
      job_name = "user-systemd";
      scrape_interval = "10s";
      static_configs = [
        {
          targets = [ "localhost:${toString port}" ];
        }
      ];
    }
  ];

  home-manager.users.eric.systemd.user.services = {
    prometheus-systemd-exporter = {
      Unit.After = [ "network.target" ];
      Service.ExecStart = ''
        ${pkgs.prometheus-systemd-exporter}/bin/systemd_exporter \
          --web.listen-address localhost:${toString port} --systemd.collector.user
      '';
      Install.WantedBy = [ "default.target" ];
    };
  };
}
