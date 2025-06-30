{ config, ... }:
let
  port = config.ports.prometheus-unifi-exporter;
  name = "unifi-exporter";
in
{
  users = {
    users."${name}" = {
      isSystemUser = true;
      group = name;
    };

    groups."${name}" = { };
  };

  sops.secrets.unifi_pw.owner = name;

  services.prometheus = {
    exporters = {
      unpoller = {
        enable = true;
        port = port;
        user = name;
        loki.url = "localhost:${toString config.ports.loki}";
        controllers = [
          {
            url = "https://localhost:${toString config.ports.unifi}";
            user = "prometheus";
            pass = config.sops.secrets.unifi_pw.path;
            verify_ssl = false;
            save_ids = true;
            save_events = true;
            save_anomalies = true;
            save_alarms = true;
          }
        ];
      };
    };

    scrapeConfigs = [
      {
        job_name = "unifi";
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
