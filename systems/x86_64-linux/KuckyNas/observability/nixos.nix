{
  config,
  lib,
  pkgs,
  ...
}:
let
  port = config.ports.prometheus-nixos-exporter;
  name = "nixos-exporter";
in
{
  users = {
    users."${name}" = {
      isSystemUser = true;
      group = name;
    };

    groups."${name}" = { };
  };

  services.prometheus.scrapeConfigs = [
    {
      job_name = "nixos";
      scrape_interval = "1m";
      static_configs = [
        {
          targets = [ "localhost:${toString port}" ];
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
        User = name;
        ExecStart = "${lib.getExe pkgs.custom.prometheus-nixos-exporter} --port ${toString port}";
      };
    };
  };
}
