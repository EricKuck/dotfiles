{ config, ... }:
let
  port = config.ports.prometheus-node-exporter;
in
{
  services.prometheus = {
    exporters = {
      node = {
        enable = true;
        port = port;
      };
    };

    scrapeConfigs = [
      {
        job_name = "node";
        scrape_interval = "10s";
        static_configs = [
          {
            targets = [ "localhost:${toString port}" ];
          }
        ];
      }
    ];
  };
}
