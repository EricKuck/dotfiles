{
  config,
  lib,
  pkgs,
  ...
}:
let
  PORT = config.ports.prometheus-nixos-exporter;
in
{
  services.prometheus.scrapeConfigs = [
    {
      job_name = "nixos";
      scrape_interval = "1m";
      static_configs = [
        {
          targets = [ "localhost:${toString PORT}" ];
        }
      ];
    }
  ];

  systemd.services = {
    prometheus-nixos-exporter = {
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];
      path = [
        pkgs.nix
        pkgs.bash
      ];
      serviceConfig = {
        Restart = "always";
        RestartSec = "60s";
        ExecStart = "${lib.getExe pkgs.custom.prometheus-nixos-exporter} --port ${toString PORT}";
      };
    };
  };
}
