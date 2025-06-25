{ config, ... }:
let
  PORT = config.ports.prometheus-nut-exporter;
in
{
  services.prometheus = {
    exporters = {
      nut = {
        enable = true;
        user = "upsmon";
        group = "upsmon";
        nutUser = config.users.users.upsmon.name;
        passwordPath = config.sops.secrets.upsmon_user_pw.path;
        port = PORT;
      };
    };

    scrapeConfigs = [
      {
        job_name = "nut";
        scrape_interval = "10s";
        metrics_path = "/ups_metrics";
        static_configs = [
          {
            targets = [ "localhost:${toString PORT}" ];
          }
        ];
      }
    ];
  };
}
