{ config, ... }:
let
  PORT = config.ports.prometheus-node-exporter;
in
{
  services.prometheus = {
    exporters = {
      node = {
        enable = true;
        port = PORT;
      };
    };

    scrapeConfigs = [
      {
        job_name = "node";
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
