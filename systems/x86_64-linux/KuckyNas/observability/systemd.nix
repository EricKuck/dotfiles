{ config, ... }:
let
  PORT = config.ports.prometheus-systemd-exporter;
in
{
  services.prometheus = {
    exporters = {
      systemd = {
        enable = true;
        port = PORT;
      };
    };

    scrapeConfigs = [
      {
        job_name = "systemd";
        scrape_interval = "10s";
        static_configs = [
          {
            targets = [ "localhost:${toString PORT}" ];
          }
        ];
      }
    ];
  };
}
